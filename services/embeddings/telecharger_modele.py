"""Télécharge le modèle — à la CONSTRUCTION, jamais au démarrage.

POURQUOI CETTE DISTINCTION COMPTE ICI PLUS QU'AILLEURS. Render endort l'offre
gratuite après quinze minutes sans requête, et la réveille sur la suivante. Un
modèle téléchargé au démarrage serait retéléchargé à CHAQUE réveil : 135 Mo
tirés depuis Hugging Face avant de pouvoir répondre, plusieurs fois par jour,
et un premier appel qui expire. Téléchargé à la construction, il est déjà sur
le disque de l'instance, et le réveil ne coûte que le chargement en mémoire.

CE QU'ON PREND, ET POURQUOI CE FICHIER-LÀ. Le dépôt officiel
`intfloat/multilingual-e5-small` publie lui-même trois exports ONNX :

  * `onnx/model.onnx`                      470 Mo, float32 — ne tient pas ;
  * `onnx/model_O4.onnx`                   235 Mo, float16 optimisé — le
    float16 est fait pour une carte graphique ; sur un processeur, onnxruntime
    le reconvertit en float32 à chaque couche, donc plus lent ET plus gourmand
    que l'int8 ;
  * `onnx/model_qint8_avx512_vnni.onnx`    118 Mo, int8 — celui qu'on prend.

SON NOM PARLE D'AVX512-VNNI, ET CE N'EST PAS UNE EXIGENCE. C'est le jeu
d'instructions VISÉ par la quantification, pas un prérequis : onnxruntime
exécute les mêmes opérateurs QLinear sur n'importe quel processeur, plus
lentement là où VNNI manque. Le résultat numérique, lui, ne change pas.

ON PRÉFÈRE LE DÉPÔT OFFICIEL AUX CONVERSIONS DE TIERS. Elles existent, elles
sont souvent bonnes, mais elles vieillissent sans prévenir et personne ne
garantit qu'elles sortent du même point de départ. Ici, les poids et leur
export ont le même auteur que le modèle.

LE VOCABULAIRE VIENT DE sentencepiece.bpe.model, ET PAS DE tokenizer.json.
Les deux portent le même vocabulaire ; le premier pèse 5 Mo et coûte 49 Mo de
mémoire, le second 17 Mo et en coûte 266 — mesurés. Sur 512 Mo, l'écart décide
si le service tient ou non. `app.py` explique en tête ce qu'il faut alors
refaire à la main, et sur quelle base on a vérifié que c'était exact.
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

from huggingface_hub import hf_hub_download

DEPOT = "intfloat/multilingual-e5-small"
DOSSIER = Path(__file__).parent / "modele"

#: (chemin dans le dépôt, nom local). Le nom local est neutre : le jour où l'on
#: changera de variante quantifiée, `app.py` n'aura pas à le savoir.
FICHIERS = [
    ("onnx/model_qint8_avx512_vnni.onnx", "model.onnx"),
    ("sentencepiece.bpe.model", "sentencepiece.bpe.model"),
]


def main() -> int:
    DOSSIER.mkdir(parents=True, exist_ok=True)

    for distant, local in FICHIERS:
        cible = DOSSIER / local
        if cible.exists():
            print(f"  déjà là   {local}")
            continue

        source = hf_hub_download(DEPOT, distant)
        # `copy` et non un lien : le cache de Hugging Face n'a aucune raison de
        # survivre à la construction, et un lien mort au réveil ne se verrait
        # qu'au premier appel.
        shutil.copyfile(source, cible)
        print(f"  {cible.stat().st_size / 1e6:6.1f} Mo  {local}")

    total = sum(f.stat().st_size for f in DOSSIER.iterdir() if f.is_file())
    print(f"Modèle prêt dans {DOSSIER} — {total / 1e6:.1f} Mo au total.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
