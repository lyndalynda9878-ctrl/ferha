"""Ferha — le service qui fabrique les empreintes (§7.1, §8.4).

CE QU'IL FAIT, ET RIEN D'AUTRE. Il reçoit du texte, il rend des vecteurs de
384 nombres. Il ne connaît aucune salle, il ne parle pas à Supabase, il ne
décide de rien. L'indexation des salles et la recherche par le sens sont le
J19 ; ce fichier est la brique en dessous.

POURQUOI ONNX, ET PAS torch. Render offre 512 Mo. `torch` seul en pèse plus de
800 une fois chargé, et `sentence-transformers` le traîne derrière lui. Le même
modèle, exporté en ONNX et quantifié en int8, tient en 118 Mo sur le disque et
se charge avec `onnxruntime`, qui ne dépend de rien d'autre que de numpy.

POURQUOI multilingual-e5-small. Les questions du J20 arrivent en français, en
darja écrite en caractères arabes, et en franco-arabe translittéré — parfois
les trois dans la même phrase. Un modèle monolingue rendrait des vecteurs sans
rapport pour « salle des fêtes Oran » et « قاعة أفراح وهران », et la recherche
par le sens ne marcherait que pour la moitié des utilisateurs.

=============================================================================
POURQUOI sentencepiece ET PAS tokenizers — C'EST CE QUI FAIT TENIR LES 512 Mo

Le premier montage lisait `tokenizer.json` avec la bibliothèque `tokenizers`.
Elle marche, elle est celle qu'on emploie d'habitude, et elle coûte 266 Mo de
mémoire résidente à elle seule — mesurés. Sur une machine à 512 Mo, elle prend
la moitié du budget pour découper des phrases.

`sentencepiece` lit le MÊME vocabulaire depuis `sentencepiece.bpe.model`, cinq
mégaoctets, et coûte 49 Mo. Le prix à payer est qu'elle rend des identifiants
« bruts » : c'est à nous de poser le décalage d'XLM-RoBERTa et les jetons
spéciaux, ce que `tokenizers` faisait toute seule.

ON NE L'A PAS SUPPOSÉ, ON L'A VÉRIFIÉ. Les deux chemins ont été comparés sur
517 textes — les trente questions de référence du J20, des fiches de salle, de
l'arabe vocalisé, des ligatures, du tatweel, des emoji, et trois cents chaînes
tirées au hasard dans trois alphabets. Zéro écart, une fois les invisibles
retirés aux deux bouts (voir `nettoyer`). Un identifiant qui aurait différé
aurait donné une empreinte différente, sans lever la moindre erreur.

=============================================================================
LES DEUX PRÉFIXES NE SONT PAS DÉCORATIFS

E5 est entraîné avec deux préfixes, « query: » devant ce qu'on cherche et
« passage: » devant ce dans quoi on cherche. Ils ne sont pas un usage : ils
font partie du modèle. Les oublier, ou les intervertir, ne lève aucune erreur
— ça dégrade simplement la recherche, silencieusement, et personne ne s'en
aperçoit avant de lire des résultats qui ont l'air « à peu près ».

C'est pour cela que [Nature] est OBLIGATOIRE dans la requête et qu'elle n'a
pas de valeur par défaut. Un défaut serait le bon la moitié du temps.

=============================================================================
LE MEAN POOLING SE FAIT SOUS LE MASQUE

Le modèle rend un vecteur PAR TOKEN — `last_hidden_state` — et non un vecteur
par texte. La moyenne ne porte que sur les tokens réels : un lot contient des
textes de longueurs différentes, donc du remplissage, et faire entrer ce
remplissage dans la moyenne ferait dépendre l'empreinte d'un texte de la
longueur de ses voisins dans le lot. Deux appels donneraient alors deux
réponses pour la même phrase.

=============================================================================
LA NORMALISATION EST CE QUI REND LE COSINUS LISIBLE

Une fois les vecteurs ramenés à la longueur 1, leur produit scalaire EST leur
cosinus. Le J19 pourra donc comparer avec l'opérateur le moins cher de
pgvector, et la commande de vérification ci-jointe se contente d'une somme de
produits.
"""

from __future__ import annotations

import hmac
import os
import unicodedata
from contextlib import asynccontextmanager
from enum import Enum
from pathlib import Path
from typing import Annotated

import numpy as np
import onnxruntime as ort
import sentencepiece as spm
from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

# -----------------------------------------------------------------------------
# Les constantes du modèle. Elles décrivent ce qui a été téléchargé à la
# construction, et changer l'une sans changer l'autre ne marcherait pas.
# -----------------------------------------------------------------------------

MODELE = "intfloat/multilingual-e5-small"

DOSSIER_MODELE = Path(__file__).parent / "modele"
FICHIER_ONNX = DOSSIER_MODELE / "model.onnx"
FICHIER_VOCAB = DOSSIER_MODELE / "sentencepiece.bpe.model"

#: 384, et c'est la seule dimension que le J19 devra déclarer à pgvector.
DIMENSIONS = 384

#: La fenêtre du modèle. Au-delà, on tronque.
TOKENS_MAX = 512

#: Combien de textes par appel. Ce n'est pas une limite de politesse : chaque
#: texte du lot occupe `longueur × 384` flottants pendant l'inférence, et 512 Mo
#: se remplissent vite. Le J19 indexe 15 salles ; 64 laisse de la marge sans
#: jamais approcher le plafond.
LOT_MAX = 64

# -----------------------------------------------------------------------------
# LA TABLE DES JETONS D'XLM-ROBERTA
#
# `sentencepiece` rend ses propres identifiants ; le modèle en attend d'autres.
# La correspondance vient de fairseq, et elle tient en deux règles :
#
#   * quatre jetons spéciaux occupent 0 à 3, dans cet ordre-là ;
#   * tout le reste est décalé de +1 par rapport à sentencepiece.
#
# LE PIÈGE EST L'INCONNU. sentencepiece rend 0 pour un caractère hors
# vocabulaire ; 0 + 1 donnerait 1, c'est-à-dire <pad>. Un texte contenant un
# caractère exotique se retrouverait donc rempli de bourrage silencieux, au
# lieu de porter des <unk>. C'est la seule ligne de ce fichier où une erreur ne
# se verrait jamais.
#
# À NOTER : `config.json` du modèle annonce pad_token_id = 0. Il a tort — c'est
# la divergence classique d'XLM-RoBERTa, dont le <pad> est à 1. Sans
# conséquence ici, le masque d'attention écartant de toute façon le bourrage,
# mais il ne faut pas « corriger » la valeur ci-dessous d'après config.json.
# -----------------------------------------------------------------------------

ID_BOS, ID_PAD, ID_EOS, ID_UNK = 0, 1, 2, 3

#: Le décalage fairseq entre sentencepiece et XLM-RoBERTa.
DECALAGE = 1

# -----------------------------------------------------------------------------
# LES INVISIBLES
#
# Espaces au sens large, caractères de contrôle, et caractères de FORMAT :
# largeur nulle, marques de direction, jointures. Ils ne se voient pas, et ils
# arrivent pour de bon — un copier-coller depuis un site arabe amène des
# marques de direction, une saisie mobile amène des espaces insécables.
#
# On les retire AUX DEUX BOUTS, et seulement là : au milieu d'une phrase, une
# marque de direction porte un sens et les deux tokeniseurs la traitent
# pareil. En fin de chaîne, en revanche, sentencepiece les ignore là où
# `tokenizers` en faisait un jeton — c'était le seul écart entre les deux.
#
# Le balayage complet d'Unicode coûte 0,15 s, une fois, au démarrage. Énumérer
# les plages à la main serait plus rapide et se tromperait un jour.
# -----------------------------------------------------------------------------

INVISIBLES = "".join(
    c
    for c in map(chr, range(0x110000))
    if unicodedata.category(c) in ("Zs", "Zl", "Zp", "Cc", "Cf") or c.isspace()
)


def nettoyer(texte: str) -> str:
    """Retire aux deux bouts tout ce qui ne se voit pas."""
    return texte.strip(INVISIBLES)


class Nature(str, Enum):
    """Ce qu'est le texte qu'on donne, et donc le préfixe qu'il reçoit.

    DEUX VALEURS, PAS TROIS. Tout ce qui est indexé est un « passage » : une
    salle aujourd'hui, peut-être un avis demain. Ce qui est tapé par quelqu'un
    qui cherche est une « query ». Ajouter une nature par type d'objet indexé
    donnerait des préfixes que le modèle n'a jamais vus à l'entraînement.
    """

    #: Ce que tape quelqu'un qui cherche — préfixe « query: ».
    QUESTION = "question"

    #: Ce dans quoi on cherche : la fiche d'une salle — préfixe « passage: ».
    SALLE = "salle"

    @property
    def prefixe(self) -> str:
        """Le préfixe d'entraînement d'E5, espace compris."""
        return "query: " if self is Nature.QUESTION else "passage: "


# -----------------------------------------------------------------------------
# Le jeton partagé
#
# L'ADRESSE RENDER EST PUBLIQUE, CE SERVICE NE DOIT PAS L'ÊTRE. Il n'y a rien
# de secret dans une empreinte, mais il y a un processeur derrière : sans
# jeton, n'importe qui peut faire tourner le calcul à notre place, et 0,1 vCPU
# gratuit s'épuise avec une seule boucle.
#
# ON REFUSE DE DÉMARRER SANS LUI, plutôt que de répondre 401 à tout le monde.
# Les deux sont sûrs ; seul le premier se voit. Un service qui démarre en
# refusant toutes les requêtes ressemble à un service en panne, et on cherche
# la panne ailleurs — un déploiement qui échoue franchement dit où regarder.
# -----------------------------------------------------------------------------

JETON = os.environ.get("EMBED_TOKEN", "")


def verifier_le_jeton(
    authorization: Annotated[str | None, Header()] = None,
) -> None:
    """Refuse tout ce qui n'apporte pas le jeton, en 401.

    LA COMPARAISON EST EN TEMPS CONSTANT. Une comparaison ordinaire s'arrête au
    premier caractère qui diffère, et le temps qu'elle met à répondre dit
    combien de caractères étaient justes. C'est la même précaution que dans
    `chargily-webhook` (J16), pour la même raison.
    """
    donne = ""
    if authorization and authorization.lower().startswith("bearer "):
        donne = authorization[7:].strip()

    if not hmac.compare_digest(donne, JETON):
        # On ne dit PAS si le jeton est absent ou faux : les deux se répondent
        # de la même façon, et distinguer apprendrait à qui essaie.
        raise HTTPException(
            status_code=401,
            detail="Jeton absent ou invalide.",
            headers={"WWW-Authenticate": "Bearer"},
        )


# -----------------------------------------------------------------------------
# Le modèle, chargé une fois
# -----------------------------------------------------------------------------


class Empreinteur:
    """Le vocabulaire et la session ONNX, et les trois gestes entre les deux."""

    def __init__(self) -> None:
        if not FICHIER_ONNX.exists() or not FICHIER_VOCAB.exists():
            raise RuntimeError(
                f"Modèle absent de {DOSSIER_MODELE}. Il se télécharge à la "
                "CONSTRUCTION : « python telecharger_modele.py » doit faire "
                "partie de la commande de build."
            )

        self.vocabulaire = spm.SentencePieceProcessor()
        self.vocabulaire.Load(str(FICHIER_VOCAB))

        options = ort.SessionOptions()
        # UN SEUL FIL. L'offre gratuite de Render donne 0,1 vCPU : plusieurs
        # fils s'y disputeraient le même dixième de processeur, et chaque fil
        # supplémentaire réserve sa propre mémoire de travail.
        options.intra_op_num_threads = 1
        options.inter_op_num_threads = 1
        # L'arène garde la mémoire qu'elle a prise au lieu de la rendre. Sur une
        # machine à 512 Mo, on préfère payer quelques millisecondes à chaque
        # appel plutôt que de voir la mémoire monter et ne jamais redescendre.
        options.enable_cpu_mem_arena = False

        self.session = ort.InferenceSession(
            str(FICHIER_ONNX),
            sess_options=options,
            providers=["CPUExecutionProvider"],
        )

        # CE MODÈLE ATTEND token_type_ids, et tous ne l'attendent pas : il est
        # exporté depuis une architecture BERT. On lit la signature plutôt que
        # de la supposer — le jour où l'on changera de fichier ONNX, c'est cette
        # ligne qui évitera un « invalid input name ».
        self.entrees = {e.name for e in self.session.get_inputs()}

    def _encoder(self, texte: str) -> list[int]:
        """Un texte propre en identifiants XLM-RoBERTa, jetons spéciaux compris."""
        bruts = self.vocabulaire.EncodeAsIds(texte)
        ids = [ID_UNK if b == 0 else b + DECALAGE for b in bruts]
        # On tronque le CONTENU à 510 pour que la séquence complète, <s> et
        # </s> compris, tienne dans les 512 du modèle.
        return [ID_BOS] + ids[: TOKENS_MAX - 2] + [ID_EOS]

    def empreindre(self, textes: list[str], nature: Nature) -> np.ndarray:
        """Rend un vecteur unitaire de 384 nombres par texte, dans l'ordre reçu."""
        sequences = [
            self._encoder(nature.prefixe + nettoyer(t)) for t in textes
        ]

        # LE BOURRAGE SE FAIT ICI, à la longueur du plus long du lot — et non à
        # 512. Une matrice de 64 × 512 quand le plus long texte en fait 40
        # coûterait treize fois le calcul nécessaire, sur un dixième de vCPU.
        largeur = max(len(s) for s in sequences)
        ids = np.full((len(sequences), largeur), ID_PAD, dtype=np.int64)
        masque = np.zeros((len(sequences), largeur), dtype=np.int64)
        for i, s in enumerate(sequences):
            ids[i, : len(s)] = s
            masque[i, : len(s)] = 1

        entrees: dict[str, np.ndarray] = {
            "input_ids": ids,
            "attention_mask": masque,
        }
        if "token_type_ids" in self.entrees:
            # Une seule phrase par texte : le second segment n'existe pas.
            entrees["token_type_ids"] = np.zeros_like(ids)

        # (lot, tokens, 384) — un vecteur PAR TOKEN.
        couche = self.session.run(["last_hidden_state"], entrees)[0]

        # LA MOYENNE SOUS LE MASQUE. On additionne les tokens réels, on divise
        # par leur nombre. `clip` évite la division par zéro d'un texte vide —
        # qui ne devrait pas arriver, la requête le refuse, mais une empreinte
        # remplie de NaN se propagerait jusqu'à pgvector sans rien casser en
        # chemin.
        masque_f = masque.astype(np.float32)[..., None]
        somme = (couche * masque_f).sum(axis=1)
        combien = np.clip(masque_f.sum(axis=1), 1e-9, None)
        moyenne = somme / combien

        # LA NORMALISATION : après elle, le produit scalaire est le cosinus.
        longueurs = np.clip(
            np.linalg.norm(moyenne, axis=1, keepdims=True), 1e-12, None
        )
        return moyenne / longueurs


#: Rempli au démarrage par le `lifespan` ci-dessous.
_empreinteur: Empreinteur | None = None


@asynccontextmanager
async def demarrage(app: FastAPI):
    """Charge le modèle AVANT d'accepter la première requête.

    C'est ce qui rend `/health` utile comme réveil : quand il répond, le modèle
    est en mémoire et la requête suivante n'attend plus. Charger paresseusement
    au premier `/embed` déplacerait simplement l'attente sur l'utilisateur, et
    Render endort le service toutes les quinze minutes.
    """
    global _empreinteur
    _empreinteur = Empreinteur()
    yield
    _empreinteur = None


app = FastAPI(
    title="Ferha — empreintes",
    description=(
        "Transforme du texte en vecteurs de 384 nombres, pour la recherche "
        "par le sens (§7.1, §8.4). Multilingue : français, arabe, darja "
        "translittéré."
    ),
    version="1.0.0",
    lifespan=demarrage,
)


# -----------------------------------------------------------------------------
# Ce qui entre, ce qui sort
# -----------------------------------------------------------------------------


class DemandeEmpreintes(BaseModel):
    """Des textes, et ce qu'ils sont."""

    textes: list[str] = Field(
        ...,
        min_length=1,
        max_length=LOT_MAX,
        description="Les textes à transformer. Au moins un, au plus 64.",
    )
    nature: Nature = Field(
        ...,
        description=(
            "« question » pour ce que tape quelqu'un qui cherche, « salle » "
            "pour ce qui est indexé. Sans valeur par défaut : un défaut serait "
            "le bon une fois sur deux, et se tromper ne lève aucune erreur."
        ),
    )


class ReponseEmpreintes(BaseModel):
    """Les vecteurs, et de quoi vérifier qu'on parle du même modèle."""

    modele: str
    dimensions: int
    prefixe: str
    vecteurs: list[list[float]]


class Sante(BaseModel):
    """Ce que rend `/health`."""

    etat: str
    modele: str
    dimensions: int
    charge: bool


# -----------------------------------------------------------------------------
# Les deux routes
# -----------------------------------------------------------------------------


@app.get("/health", response_model=Sante, summary="Réveil et état")
def sante() -> Sante:
    """Répond SANS jeton — c'est tout l'objet de cette route.

    Render endort l'offre gratuite après quinze minutes, et la réveille sur une
    requête. Le réveilleur n'a pas à connaître le jeton : il ne demande rien
    d'autre que « êtes-vous là ». Rien ici ne parle des salles, du modèle
    au-delà de son nom, ni de quoi que ce soit qu'un inconnu ne puisse lire.
    """
    return Sante(
        etat="ok",
        modele=MODELE,
        dimensions=DIMENSIONS,
        charge=_empreinteur is not None,
    )


@app.post(
    "/embed",
    response_model=ReponseEmpreintes,
    dependencies=[Depends(verifier_le_jeton)],
    summary="Fabrique les empreintes",
)
def embed(demande: DemandeEmpreintes) -> ReponseEmpreintes:
    """Rend un vecteur unitaire de 384 nombres par texte, dans l'ordre reçu."""
    if _empreinteur is None:  # pragma: no cover — le lifespan l'a rempli
        raise HTTPException(status_code=503, detail="Modèle pas encore chargé.")

    # Un texte vide n'a pas d'empreinte : il rendrait le vecteur du seul
    # préfixe, c'est-à-dire le même pour toutes les salles vides. Mieux vaut le
    # refuser que de l'indexer. On juge sur le texte NETTOYÉ : une chaîne faite
    # de seules marques de direction est vide, même si elle n'est pas « ».
    if any(not nettoyer(t) for t in demande.textes):
        raise HTTPException(
            status_code=400,
            detail="Un texte vide n’a pas d’empreinte.",
        )

    vecteurs = _empreinteur.empreindre(demande.textes, demande.nature)

    return ReponseEmpreintes(
        modele=MODELE,
        dimensions=DIMENSIONS,
        prefixe=demande.nature.prefixe,
        vecteurs=vecteurs.tolist(),
    )
