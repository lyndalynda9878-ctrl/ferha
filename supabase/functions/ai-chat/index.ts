// =============================================================================
// Ferha — Edge Function « ai-chat » (§8.1, §8.5 ; §4.2 CLI-02)
//
// L'agent de recherche. Quatre temps, et chacun fait ce qu'il sait faire :
//
//   1. Le MODÈLE extrait les critères de la question. Sortie structurée.
//   2. Le SQL fait le tri EXACT — wilaya, capacité, budget, disponibilité.
//   3. Le VECTEUR classe ce qui reste. Aucun seuil.
//   4. Le MODÈLE rédige, à partir des salles trouvées et de rien d'autre.
//
// CE QUE LE MODÈLE NE FAIT JAMAIS : une affirmation factuelle vérifiable. La
// comparaison de dates, le report d'année, l'annonce de l'hypothèse, le prix —
// tout cela se calcule ici ou en SQL. Il rédige, il n'atteste pas.
//
// LA LIGNE DE PARTAGE EST AU §8.1 : « la similarité ne sait pas compter ».
// Elle rapprochera « 300 personnes » de « 250 personnes » et proposera une
// salle déjà réservée. On ne lui confie donc jamais un chiffre — seulement le
// flou : « moderne », « avec un jardin », « près de la mer ».
//
// C'EST POURQUOI LES NOMBRES REMONTENT UN À UN DANS LE SQL. Le jour de la
// semaine, le nombre de places de parking et « la moins chère » partaient
// encore au vecteur au J20, et il les a tous perdus : un prix de dimanche pour
// une question sur un samedi, les parkings de 75 et 55 places proposés quand la
// base en a un de 150. Chacun a maintenant son champ, son filtre ou son tri.
//
// =============================================================================
// LE MODÈLE : gemini-3.5-flash-lite
//
// Palier gratuit (« Free of charge » sur la page de tarification), et décrit
// par Google comme fait pour « high-volume agentic workflows, simple data
// extraction » — c'est-à-dire exactement l'étape 1. L'étape 4 est très
// contrainte : le modèle n'a pas à réfléchir, il a à obéir et à écrire trois
// phrases dans la bonne langue. Sur ce travail-là, un modèle plus gros coûte
// des quotas sans rien apporter.
//
// LE NOM EST SURCHARGEABLE par un secret GEMINI_MODEL, sans redéploiement : si
// le darja se révèle mal extrait, passer à gemini-3.8-flash est une ligne dans
// le tableau de bord.
//
// =============================================================================
// L'API : /v1beta/interactions
//
// Ce n'est plus `:generateContent` avec `generationConfig.responseSchema`. La
// forme retenue est celle que documentent le démarrage rapide ET la page des
// sorties structurées : un POST sur `/v1beta/interactions`, la clé dans
// l'en-tête `x-goog-api-key`, le modèle dans le corps, et la contrainte de
// forme dans `response_format`. Le texte revient dans `output_text`.
//
// `store: false` : on ne laisse aucune conversation côté Google. Le §8.5 veut
// un journal chez nous, pas chez le fournisseur.
//
// =============================================================================
// LES GARDE-FOUS (§8.5)
//
// UN NOM PROPRE NE SE COUPE PAS. La règle 9 vaut pour les salles, les communes
// et les wilayas : le nom s'écrit en latin comme la base le porte, ou
// entièrement en arabe quand la base en donne la forme — `wilaya_name_ar`, et
// elle seule. Le banc le vérifie mot par mot, c'est son quatrième contrôle.
//
// CONTRÔLE PRINCIPAL : LES IDENTIFIANTS que le modèle déclare. C'est le seul
// qui ne dépende ni de la langue ni de l'écriture — une réponse en arabe
// translitère les noms, et aucune comparaison latine ne les y retrouve.
//
// FILET SECONDAIRE : LES NOMS dans la prose, en écriture latine seulement.
//
// LA LANGUE DE LA RÉPONSE EST CELLE DE LA QUESTION, et ni l'une ni l'autre ne
// se demande plus au modèle. L'ÉCRITURE DE LA QUESTION SE COMPTE ici : une
// question en caractères arabes est en arabe, quoi qu'il en dise — il disait
// « mixte », et « mixte » veut dire « réponds en français ». LA RÉPONSE se
// compte de même, noms propres retirés d'abord, puisque la règle 9 les impose
// en latin. Ne reste au modèle que le jugement qu'aucun comptage ne rend :
// séparer le français du franco-arabe translittéré.
//
// AUCUN APPEL AU CONTACT DIRECT (§9). « Contactez les propriétaires pour
// vérifier la disponibilité » invite à contourner la plateforme, et il n'y a
// de toute façon personne à joindre : le téléphone ne sort qu'après acceptation.
// Le seul geste proposé est celui de l'application — ouvrir la fiche, envoyer
// une demande.
//
// AU DEUXIÈME ÉCHEC, ON REND LA LISTE BRUTE. Pas de troisième essai : si le
// modèle s'obstine, le problème est le prompt, et faire patienter
// l'utilisateur une seconde de plus ne le résoudra pas. Une liste sans phrase
// est moins agréable, elle n'est pas fausse.
//
// AUCUN PRIX INVENTÉ : les montants arrivent déjà calculés de
// `salles_pour_agent()`. Le modèle reçoit des nombres, il n'en fabrique pas.
//
// JAMAIS UNE SALLE NON PUBLIÉE : le tri exact ne rend que des salles publiées,
// et la validation des noms porte sur le catalogue ENTIER — brouillons compris.
//
// SECRETS À POSER DANS SUPABASE (Edge Functions → Secrets) :
//   GEMINI_API_KEY               la clé du modèle — le seul secret à créer
//   GEMINI_MODEL                 facultatif, pour changer de modèle sans code
//   EMBEDDINGS_URL               déjà posé au J19
//   EMBED_TOKEN                  déjà posé au J19
//   SUPABASE_URL                 fournies d'office par la plateforme
//   SUPABASE_SERVICE_ROLE_KEY
// =============================================================================

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/interactions";
const MODELE_PAR_DEFAUT = "gemini-3.5-flash-lite";

/// LES EN-TÊTES CORS, ET POURQUOI ILS ARRIVENT SEULEMENT MAINTENANT.
///
/// Jusqu'au J20, cette fonction n'était appelée que par le banc des 30
/// questions — un script PowerShell, qui n'est pas un navigateur et ne demande
/// donc aucune permission. L'écran 8 change cela : la page Flutter web est
/// servie depuis `localhost`, la fonction depuis `*.supabase.co`, et le
/// navigateur envoie d'abord un OPTIONS de pré-vol. Sans réponse à ce pré-vol,
/// l'appel n'a PAS LIEU — et il n'échoue même pas d'une façon qu'on puisse
/// afficher : il ne part jamais.
///
/// Ce sont les mêmes en-têtes que « create-checkout », posés pour la même
/// raison et dans les mêmes termes.
const ENTETES_CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/// Combien de salles le modèle voit — et donc au plus combien il en cite.
///
/// CINQ, ET NON HUIT. Le §8.1 en suggère huit, mais une réponse qui en énumère
/// huit n'a rien choisi : c'est un annuaire, pas un conseil. On coupe le
/// CONTEXTE à cinq plutôt que de demander au modèle de se limiter — une
/// consigne se néglige, un contexte absent ne se cite pas.
const SALLES_MAX = 5;

/// Et trois quand la question porte sur le prix. Voir l'appel à
/// `salles_pour_agent` : une liste classée par prix n'a d'intérêt qu'en tête.
const SALLES_PRIX_BAS = 3;

/// Un rejeu, pas deux. Voir l'en-tête.
const REJEUX_MAX = 1;

const DELAI_EMPREINTES_MS = 90_000;
const DELAI_MODELE_MS = 60_000;

/// Les dix codes d'équipement de la base. Le modèle choisit dans cette liste
/// et nulle part ailleurs : un code inventé ne filtrerait rien, en silence.
const EQUIPEMENTS = [
  "chambre_mariee", "climatisation", "cuisine_equipee", "decoration_florale",
  "dj", "espace_femmes", "groupe_electrogene", "jardin", "sono", "traiteur_libre",
];

const TYPES_EVENEMENT = [
  "mariage", "fiancailles", "henne", "circoncision", "anniversaire",
];

const CRENEAUX = ["midi", "soir", "journee"];

/// Les jours de la semaine, dans l'ordre de `Date.getUTCDay()` décalé : l'index
/// 0 y est dimanche, et c'est `JOURS_ISO` qui garde cet ordre-là.
const JOURS_SEMAINE = [
  "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche",
];

/// Indexé comme `Date.getUTCDay()` : 0 = dimanche.
const JOURS_ISO = [
  "dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi",
];

const JOURS_AR: Record<string, string> = {
  lundi: "الإثنين", mardi: "الثلاثاء", mercredi: "الأربعاء", jeudi: "الخميس",
  vendredi: "الجمعة", samedi: "السبت", dimanche: "الأحد",
};

/// LE PARCOURS DE RÉSERVATION, EN DUR ET EN COURT.
///
/// L'agent ne savait pas répondre à « comment je bloque une date ? » : personne
/// ne le lui avait appris, et il comblait en listant des salles — hors sujet.
///
/// C'est l'usage « Support & FAQ » du §8.2, qui s'appuie sur `kb_documents` et
/// n'existe pas encore. En attendant, ces six lignes suffisent, et elles ont un
/// avantage sur un RAG : elles ne peuvent pas se tromper. Le jour où
/// `kb_documents` arrivera, c'est cette constante qui disparaîtra.
const PROCEDURE = `Comment réserver sur Ferha :
1. Vous envoyez une demande à la salle : la date, le créneau, le nombre d'invités.
2. Le propriétaire répond sous 48 heures — il accepte ou il refuse.
3. S'il accepte, vous versez un acompte de 25 % du montant convenu.
4. Vous avez 72 heures pour le faire : c'est l'option, et elle tient la date pour vous.
5. L'acompte se paie par carte CIB ou Edahabia, ou en espèces sur place.
6. La réservation est confirmée une fois l'acompte encaissé.`;

/// LE MÊME PARCOURS, EN ARABE, ET EN DUR LUI AUSSI.
///
/// Il ne sert pas à répondre d'habitude — le modèle traduit très bien — mais à
/// GARANTIR. Quand la traduction perd un repère, c'est ce texte-ci qui part,
/// et une personne qui écrit en arabe mérite le repli dans sa langue, pas un
/// paragraphe français.
const PROCEDURE_AR = `كيفاش تحجز في فرحة:
1. تبعث طلب للقاعة: التاريخ، الفترة، وعدد المدعوين.
2. صاحب القاعة يرد في ظرف 48 ساعة — يقبل ولا يرفض.
3. إذا قبل، تدفع تسبيق 25 % من المبلغ المتفق عليه.
4. عندك 72 ساعة باش تدفعه: هذا هو الخيار، وهو اللي يحجز لك التاريخ.
5. التسبيق يتدفع ببطاقة CIB ولا الذهبية، ولا نقدا في عين المكان.
6. الحجز يتأكد كي يوصل التسبيق.`;

/// LES QUATRE REPÈRES D'UNE RÉPONSE DE PROCÉDURE.
///
/// Le modèle reformulait le parcours et laissait tomber l'option de 72 heures —
/// c'est-à-dire le délai au bout duquel la date se libère. Un oubli qui coûte
/// une salle.
///
/// On ne le lui demande donc plus seulement : on vérifie. Trois nombres et un
/// moyen de paiement, et à défaut c'est le texte de référence qui part, mot
/// pour mot. Le §8.5 dit que le modèle rédige et n'atteste pas ; un parcours de
/// réservation est une attestation.
const REPERES_PROCEDURE = ["48", "25", "72"];
const MOYEN_DE_PAIEMENT = /cib|edahabia|dahabia|ذهبي|نقد|espece/;

const WILAYAS =
  "01 Adrar, 02 Chlef, 03 Laghouat, 04 Oum El Bouaghi, 05 Batna, 06 Béjaïa, " +
  "07 Biskra, 08 Béchar, 09 Blida, 10 Bouira, 11 Tamanrasset, 12 Tébessa, " +
  "13 Tlemcen, 14 Tiaret, 15 Tizi Ouzou, 16 Alger, 17 Djelfa, 18 Jijel, " +
  "19 Sétif, 20 Saïda, 21 Skikda, 22 Sidi Bel Abbès, 23 Annaba, 24 Guelma, " +
  "25 Constantine, 26 Médéa, 27 Mostaganem, 28 M'Sila, 29 Mascara, " +
  "30 Ouargla, 31 Oran, 32 El Bayadh, 33 Illizi, 34 Bordj Bou Arreridj, " +
  "35 Boumerdès, 36 El Tarf, 37 Tindouf, 38 Tissemsilt, 39 El Oued, " +
  "40 Khenchela, 41 Souk Ahras, 42 Tipaza, 43 Mila, 44 Aïn Defla, 45 Naâma, " +
  "46 Aïn Témouchent, 47 Ghardaïa, 48 Relizane, 49 Timimoun, " +
  "50 Bordj Badji Mokhtar, 51 Ouled Djellal, 52 Béni Abbès, 53 In Salah, " +
  "54 In Guezzam, 55 Touggourt, 56 Djanet, 57 El M'Ghair, 58 El Meniaa";

// -----------------------------------------------------------------------------
// Les schémas de sortie structurée
//
// AUCUN TYPE NULLABLE, ET C'EST DÉLIBÉRÉ. Les dialectes de JSON Schema ne
// s'accordent pas sur `"type": ["string", "null"]`, et une contrainte refusée
// par le fournisseur ferait échouer l'appel entier. On demande donc des chaînes
// vides et des zéros, et c'est ici qu'on les retraduit en « non renseigné ».
// -----------------------------------------------------------------------------

const SCHEMA_CRITERES = {
  type: "object",
  properties: {
    hors_sujet: { type: "boolean" },
    question_procedure: { type: "boolean" },
    langue: { type: "string", enum: ["fr", "ar", "mixte"] },
    date_origine: {
      type: "string",
      enum: ["aucune", "explicite", "annee_absente", "relative"],
    },
    wilaya_code: { type: "string" },
    commune: { type: "string" },
    date: { type: "string" },
    creneau: { type: "string" },
    invites: { type: "integer" },
    budget_max: { type: "integer" },
    type_evenement: { type: "string" },
    equipements: { type: "array", items: { type: "string" } },
    jour_semaine: { type: "string", enum: ["", ...JOURS_SEMAINE] },
    parking_min: { type: "integer" },
    parking_flou: { type: "boolean" },
    prix_bas: { type: "boolean" },
    soft_query: { type: "string" },
  },
  required: [
    "hors_sujet", "question_procedure", "langue", "date_origine",
    "jour_semaine", "parking_min", "parking_flou", "prix_bas",
    "equipements", "soft_query",
  ],
};

const SCHEMA_REPONSE = {
  type: "object",
  properties: {
    reponse: { type: "string" },
    venue_ids: { type: "array", items: { type: "string" } },
  },
  required: ["reponse", "venue_ids"],
};

type Criteres = {
  hors_sujet: boolean;
  question_procedure: boolean;
  langue: string;
  date_origine: string;
  /// Vrai dès que l'année n'était pas dans la question. La réponse le dit.
  annee_supposee: boolean;
  wilaya_code: string;
  commune: string;
  date: string;
  creneau: string;
  invites: number;
  budget_max: number;
  type_evenement: string;
  equipements: string[];
  /// Le jour de la semaine nommé par la question. Vide s'il n'y en a pas.
  jour_semaine: string;
  /// Vrai quand c'est ce jour-là qui a fixé la date — la réponse le dit.
  jour_impose: boolean;
  /// Un nombre de places exigé ; 0 quand la question n'en donne aucun.
  parking_min: number;
  /// « beaucoup de parking », sans chiffre : un ordre de tri, pas un filtre.
  parking_flou: boolean;
  /// « la moins chère » : un ordre de tri, et une liste plus courte.
  prix_bas: boolean;
  soft_query: string;
};

type Salle = {
  venue_id: string;
  name: string;
  commune: string;
  wilaya_name: string;
  /// La photo de couverture — chemin de Storage ou URL. Elle part vers
  /// l'APPLICATION, qui en fait une carte, et jamais vers le modèle : voir la
  /// migration 031. Une photo s'affiche, elle ne se raconte pas.
  cover_photo: string | null;
  /// La forme arabe du nom de wilaya, pour qu'une reponse en arabe l'ecrive
  /// entierement en arabe. Les salles et les communes n'en ont pas.
  wilaya_name_ar: string | null;
  capacity_seated: number;
  parking_spaces: number | null;
  amenity_codes: string[] | null;
  price: string | number | null;
  price_slot: string | null;
  rating: string | number | null;
  review_count: number;
  proximite: number | null;
};

// -----------------------------------------------------------------------------
// Outils
// -----------------------------------------------------------------------------

function reponseHttp(corps: unknown, statut = 200): Response {
  return new Response(JSON.stringify(corps), {
    status: statut,
    headers: { ...ENTETES_CORS, "Content-Type": "application/json" },
  });
}

/// Minuscules, sans accents, espaces normalisés. Sert à comparer un nom de
/// salle écrit par le modèle au nom que porte la base : « Complexe Chréa » et
/// « complexe chrea » doivent se reconnaître.
function aplatir(texte: string): string {
  return texte
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[\u2019']/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/// Le cœur distinctif d'un nom : « Salle El Bahia » → « el bahia ».
///
/// On retire le mot générique de tête parce que le modèle l'omet souvent —
/// « El Bahia peut vous accueillir » — et qu'une salle citée sans son préfixe
/// reste une salle citée.
function coeurDuNom(nom: string): string {
  const plat = aplatir(nom);
  return plat.replace(/^(salle|palais|residence|complexe|espace)\s+/, "");
}

/// Les mots qu'un nom de salle peut porter et qui ne designent personne.
const MOTS_COMMUNS = new Set([
  "salle", "salles", "palais", "residence", "complexe", "espace", "espaces",
  "jardin", "mariage", "mariages", "fete", "fetes", "reve", "reves",
]);

/// Un coeur de nom est-il assez distinctif pour etre cherche dans une phrase ?
///
/// UNE SALLE QUI S'APPELLE « salle » NE SE DISTINGUE PAS DU NOM COMMUN. Le
/// catalogue en contient une, et le validateur voyait donc une salle citee hors
/// contexte dans toute phrase francaise parlant de salles : l'agent, qui avait
/// bien repondu, retombait sur la liste brute a chaque question.
///
/// Aucune comparaison de chaines ne peut trancher ce cas — le mot est le meme.
/// On renonce donc au controle PAR LE NOM pour ces salles-la, et on s'en remet
/// au controle par IDENTIFIANT, qui reste entier. Elles ne sont de toute facon
/// jamais dans un contexte tant qu'elles ne sont pas publiees.
function coeurUtilisable(coeur: string): boolean {
  if (coeur.length < 5) return false;
  return !coeur.split(" ").every((mot) => MOTS_COMMUNS.has(mot));
}

/// Avance une date d'année en année jusqu'à ce qu'elle soit à venir.
///
/// « LE 14 AOÛT » VEUT DIRE LE PROCHAIN 14 AOÛT, jamais celui de l'an dernier.
/// Le modèle se trompait dessus — il rendait l'année en cours, déjà passée — et
/// l'agent répondait « cette date est passée » à quelqu'un qui demandait un prix.
/// On ne lui confie donc plus ce calcul : il dit seulement SI l'année était dans
/// la question, et l'arithmétique se fait ici.
///
/// LE 29 FÉVRIER SE RÈGLE TOUT SEUL : la date inexistante d'une année commune est
/// refusée, et la boucle continue jusqu'à la prochaine bissextile.
function avancerJusquAVenir(date: string, aujourdHui: string): string {
  let annee = Number(date.slice(0, 4));
  const jourEtMois = date.slice(4);

  for (let essai = 0; essai < 10; essai++) {
    const candidate = String(annee).padStart(4, "0") + jourEtMois;
    // Une date inexistante ne revient pas telle quelle de `toISOString`.
    const valide =
      new Date(candidate + "T00:00:00Z").toISOString().slice(0, 10) === candidate;
    if (valide && candidate >= aujourdHui) return candidate;
    annee++;
  }
  return date;
}

/// La prochaine date À VENIR qui tombe un jour de semaine donné.
///
/// « UN SAMEDI SOIR EN AOÛT » EST UNE DEMANDE CHIFFRÉE, et le prix en dépend :
/// le week-end porte une majoration que le dimanche ne porte pas. L'agent
/// répondait avec le prix du 1er août 2027 — un dimanche — à qui demandait un
/// samedi. Le modèle n'avait pas tort de rendre le 1er : personne ne lui avait
/// dit que le jour de la semaine comptait, et il n'avait pas de calendrier.
///
/// LE MOIS SURVIT AU JOUR. Quand la question nomme un mois, on ne prend pas le
/// samedi de la semaine prochaine : on cherche le premier samedi À VENIR qui
/// tombe dans ce mois-là. Sans mois, c'est simplement le prochain.
///
/// La boucle couvre huit ans — assez pour un mois qui vient de passer, et pour
/// le cas où l'on chercherait un 29 février tombant un mardi.
function prochaineDateAuJour(
  jour: string,
  aujourdHui: string,
  mois: number | null,
): string {
  const cible = JOURS_ISO.indexOf(jour);
  if (cible < 0) return "";

  const depart = new Date(aujourdHui + "T00:00:00Z").getTime();
  for (let i = 0; i < 3000; i++) {
    const jourCandidat = new Date(depart + i * 86_400_000);
    if (jourCandidat.getUTCDay() !== cible) continue;
    if (mois && jourCandidat.getUTCMonth() + 1 !== mois) continue;
    return jourCandidat.toISOString().slice(0, 10);
  }
  return "";
}

/// Les chiffres arabes-indiens ramenés aux nôtres, pour pouvoir chercher « 72 »
/// dans une phrase qui l'écrit « ٧٢ ».
function chiffresLatins(texte: string): string {
  return texte
    .replace(/[\u0660-\u0669]/g, (c) => String(c.charCodeAt(0) - 0x0660))
    .replace(/[\u06f0-\u06f9]/g, (c) => String(c.charCodeAt(0) - 0x06f0));
}

/// Les quatre repères sont-ils tous là ? Voir REPERES_PROCEDURE.
function procedureComplete(texte: string): boolean {
  if (!texte) return false;
  const avecChiffres = chiffresLatins(texte);
  return REPERES_PROCEDURE.every((r) => avecChiffres.includes(r)) &&
    MOYEN_DE_PAIEMENT.test(aplatir(avecChiffres));
}

/// Echappe ce qui a un sens dans une expression reguliere.
function echapper(texte: string): string {
  return texte.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

async function rpc(
  url: string,
  cle: string,
  fonction: string,
  parametres: Record<string, unknown>,
): Promise<unknown> {
  const appel = await fetch(`${url}/rest/v1/rpc/${fonction}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: cle,
      Authorization: `Bearer ${cle}`,
    },
    body: JSON.stringify(parametres),
  });

  if (!appel.ok) {
    throw new Error(
      `${fonction} a échoué (${appel.status}) : ${await appel.text().catch(() => "")}`,
    );
  }
  return await appel.json();
}

/// Un appel au modèle, avec contrainte de forme. Rend l'objet décodé.
///
/// LE 429 REMONTE TEL QUEL, avec son nom. C'est le seul code que l'appelant
/// doit distinguer : il ne veut pas dire « panne » mais « revenez plus tard »,
/// et l'utilisateur a droit à une phrase, pas à une trace.
class QuotaEpuise extends Error {}

async function demanderAuModele(
  cle: string,
  modele: string,
  instruction: string,
  entree: string,
  schema: unknown,
): Promise<Record<string, unknown>> {
  const appel = await fetch(GEMINI_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": cle,
    },
    body: JSON.stringify({
      model: modele,
      system_instruction: instruction,
      input: entree,
      // On ne laisse rien côté fournisseur : le journal du §8.5 est chez nous.
      store: false,
      response_format: {
        type: "text",
        mime_type: "application/json",
        schema,
      },
    }),
    signal: AbortSignal.timeout(DELAI_MODELE_MS),
  });

  if (appel.status === 429) throw new QuotaEpuise("429");

  if (!appel.ok) {
    throw new Error(
      `le modèle a rendu ${appel.status} : ${await appel.text().catch(() => "")}`,
    );
  }

  const brut = await appel.json();
  // `output_text` est la propriété de confort ; on retombe sur le dernier pas
  // si elle manque, parce qu'une forme de réponse peut évoluer.
  const texte: string = brut?.output_text ??
    brut?.steps?.[brut.steps.length - 1]?.content?.[0]?.text ?? "";

  if (!texte) throw new Error("le modèle a rendu une réponse vide");

  return JSON.parse(texte);
}

// -----------------------------------------------------------------------------
// Les deux instructions système
// -----------------------------------------------------------------------------

function instructionExtraction(aujourdHui: string): string {
  return `Tu analyses la question d'une personne qui cherche une salle des fêtes en Algérie.
Tu n'écris AUCUNE phrase : tu remplis seulement les champs demandés.

La question peut être en français, en arabe standard, en arabe dialectal algérien (darja),
ou en franco-arabe translittéré ("kayen salle f wahran", "rani nqalab 3la", "3andkom", "wach").
Comprends les trois de la même façon.

AUJOURD'HUI : ${aujourdHui}. Les dates relatives se calculent par rapport à ce jour.

CHAMPS :
- hors_sujet : true UNIQUEMENT si la question ne concerne ni une salle des fêtes,
  ni une réservation, ni le fonctionnement du service. La météo, le sport, la cuisine
  sont hors sujet. "comment réserver ?" n'est PAS hors sujet.
- question_procedure : true quand la question porte sur le FONCTIONNEMENT du service
  et non sur une salle en particulier : comment réserver, comment bloquer une date,
  quel acompte, quel délai, comment payer, comment annuler. "kifach ndir bach nhabes
  date" et "كيفاش نحجز" sont des questions de procédure.
- langue : "fr" si la question est en français, "ar" si elle est en caractères arabes,
  "mixte" si elle est en caractères LATINS et mêle français et arabe translittéré
  ("kayen salle f wahran"). L'écriture arabe est recomptée après toi et l'emporte
  sur ce que tu réponds ici : ce qui t'appartient vraiment, c'est de séparer "fr"
  de "mixte", que rien dans l'alphabet ne distingue.
- wilaya_code : le code à deux chiffres, depuis cette liste : ${WILAYAS}.
  Chaîne vide si aucune wilaya n'est nommée. Reconnais les noms en arabe
  (وهران = 31, الجزائر = 16, سطيف = 19, قسنطينة = 25, البليدة = 09)
  et les translittérations (wahran, alger, setif, constantine, blida, tizi ouzou).
  Une COMMUNE citée sans wilaya (Chéraga, Zéralda, Boufarik, Birtouta, El Khroub,
  Aïn El Turck, Bir El Djir, Ouled Yaïch) va dans "commune", pas dans wilaya_code.
- commune : le nom de la commune si la question en cite une. Chaîne vide sinon.
- date : "AAAA-MM-JJ" si la question donne une date, même relative ("demain", "hier",
  "le 14 août"). Si l'année manque, prends la PROCHAINE occurrence À VENIR — jamais
  une date déjà passée. Chaîne vide si aucune date.
  Quand la question nomme un MOIS sans jour du mois ("un samedi soir en août"),
  remplis quand même ce champ avec le 1er de ce mois : c'est le mois qui compte
  ici, et jour_semaine dira le reste.
- date_origine : d'où vient cette date.
  "aucune"        : la question ne donne aucune date.
  "explicite"     : la question donne le jour, le mois ET l'année.
  "annee_absente" : la question donne le jour et le mois sans l'année
                    ("le 14 aout", "un samedi soir en aout").
  "relative"      : la date se compte depuis aujourd'hui ("hier", "demain").
  Ce champ compte autant que la date : c'est lui qui dit si l'on a le droit de
  corriger l'année.
- creneau : "midi", "soir" ou "journee". Chaîne vide si non précisé.
- invites : le nombre de personnes attendues. 0 si non précisé.
- budget_max : le budget maximum en dinars, en nombre entier. 0 si non précisé.
- type_evenement : un seul parmi ${TYPES_EVENEMENT.join(", ")}. Chaîne vide sinon.
  "عرس" et "3ors" = mariage. "عقيقة" et "aqiqa" = circoncision.
- equipements : les codes demandés, uniquement parmi ${EQUIPEMENTS.join(", ")}.
  Tableau vide si aucun. "parking" n'est PAS un équipement : c'est une colonne
  chiffrée, et elle a ses deux champs à elle, juste en dessous.
- jour_semaine : le jour de la semaine que nomme la question, parmi
  ${JOURS_SEMAINE.join(", ")}. Reconnais l'arabe (السبت = samedi, الجمعة = vendredi,
  الأحد = dimanche) et le translittéré ("nhar essebt", "jem3a"). Chaîne vide si la
  question ne nomme aucun jour. "un samedi soir en août" donne "samedi".
  CE CHAMP COMPTE : le prix d'un samedi n'est pas celui d'un dimanche.
- parking_min : le nombre minimal de places de parking quand la question donne un
  chiffre ("un parking d'au moins 100 voitures"). 0 sinon.
- parking_flou : true quand la question demande BEAUCOUP de parking sans donner de
  chiffre — "un grand parking", "de la place pour les voitures", "بلاصة
  للطوموبيلات بزاف". false sinon. "avec parking" tout court n'est ni l'un ni
  l'autre : laisse les deux champs vides.
- prix_bas : true quand la personne cherche ce qui coûte le moins — "la moins
  chère", "pas cher", "rkhisa", "قاعة رخيصة", "un petit budget". false sinon. Un
  budget CHIFFRÉ va dans budget_max ; les deux peuvent être remplis ensemble.
- soft_query : ce qui reste et qui ne se filtre pas — l'ambiance, le style, la
  proximité de la mer. Reformule-le en quelques mots dans la langue de la
  question. Chaîne vide s'il n'y a rien de tel. Le parking et le prix bas n'y
  vont plus : ils ont désormais leurs propres champs.

N'invente aucun critère qui ne soit pas dans la question.`;
}

function instructionRedaction(): string {
  return `Tu es l'assistant de Ferha, une application algérienne de réservation de salles des fêtes.
Tu écris une réponse courte — trois à cinq phrases — à la personne qui a posé la question.

RÈGLES ABSOLUES :
1. Tu ne parles QUE des salles listées dans le contexte. Aucune autre salle n'existe.
   Ne cite jamais un nom de salle qui n'est pas dans la liste, même à titre d'exemple.
2. Les prix sont ceux du contexte, au dinar près. Tu ne calcules rien, tu ne convertis
   rien, tu n'arrondis rien. Si une salle n'a pas de prix dans le contexte, n'en donne pas.
3. Si la liste est vide, dis franchement qu'aucune salle ne correspond, et pourquoi
   (wilaya sans salle, capacité trop grande, budget trop bas). Puis ARRÊTE-TOI.
   Ne renvoie vers rien : ni « les autres salles de cette wilaya », ni « les communes
   voisines », ni « revenez plus tard ». Tu ne sais pas ce qu'il y a ailleurs, et
   inviter à consulter ce qui n'existe pas est une faute aussi grave qu'inventer
   une salle.
3 bis. Tu cites au plus CINQ salles, les premières de la liste — elle est déjà
   classée de la plus pertinente à la moins. Une bonne réponse choisit ; une
   énumération de tout ce qui existe est un annuaire, pas un conseil.
4. TU NE RENVOIES JAMAIS VERS UN CONTACT DIRECT. Ni « contactez le propriétaire »,
   ni « appelez la salle », ni « renseignez-vous auprès de », ni un numéro de
   téléphone. Le téléphone N'EXISTE PAS à ce stade : il ne se donne qu'une fois
   la demande ACCEPTÉE.
   LE SEUL GESTE QUE TU PROPOSES EST CELUI DE L'APPLICATION : ouvrir la fiche de
   la salle et envoyer une demande. C'est là que le propriétaire confirmera la
   disponibilité, et nulle part ailleurs. Tu ne promets donc aucune
   disponibilité, et tu n'invites à joindre personne.
   Le plus souvent, la bonne fin de réponse est de n'en pas avoir : tu présentes
   les salles, et tu t'arrêtes.
5. Réponds dans la LANGUE DE LA QUESTION. Si elle est en arabe, réponds en arabe.
   Si elle mélange français et arabe translittéré, réponds en français simple.
6. venue_ids doit contenir, dans l'ordre où tu les cites, les identifiants exacts
   des salles dont tu parles — et eux seuls. C'EST LE CHAMP LE PLUS IMPORTANT :
   il est vérifié, et une réponse dont les identifiants ne correspondent pas aux
   salles nommées est rejetée. Si tu ne nommes aucune salle, laisse-le vide.
7. N'annonce PAS toi-même qu'une année a été supposée : la phrase est ajoutée
   avant la tienne, avec la bonne date. Commence directement par ta réponse.
8. Quand on te donne un texte de PROCÉDURE, réponds uniquement avec lui, dans la
   langue de la question, et ne nomme AUCUNE salle — venue_ids reste vide.
9. UN NOM PROPRE NE SE COUPE JAMAIS ENTRE DEUX ÉCRITURES. Ni un nom de salle,
   ni une commune, ni une wilaya. "البلida" et "ابن خaldoun" sont des mots que
   personne ne peut lire, et que personne ne retrouvera en cherchant.
   Il n'y a que DEUX façons correctes de l'écrire :
   — EN ÉCRITURE LATINE, exactement comme le contexte le porte, lettre pour
     lettre : "Salle Ibn Khaldoun", "Complexe Chréa", "Ouled Yaïch". Tu peux le
     faire précéder d'un mot arabe — قاعة Salle El Bahia, بلدية Ouled Yaïch —
     le nom lui-même reste latin.
   — ENTIÈREMENT EN ARABE, et UNIQUEMENT si le contexte te donne cette forme.
     Le champ "wilaya_ar" te la donne pour la wilaya : ولاية البليدة, en entier.
   LES NOMS DE SALLE ET LES COMMUNES N'ONT AUCUNE FORME ARABE dans le contexte :
   ils s'écrivent donc toujours en latin. Ne les translitère pas, ne les devine
   pas de mémoire — c'est en la devinant qu'on coupe un mot en deux.
10. TU NE DIS D'UNE SALLE QUE CE QUE LE CONTEXTE CONTIENT — sa commune, sa
   wilaya, sa capacité, ses équipements, son prix, sa note. Tu peux les
   reformuler, jamais les compléter. Si le contexte ne dit pas qu'elle est près de la mer, qu'elle
   est moderne, qu'elle a une belle vue ou un parking fermé, tu ne le dis pas.
   INVENTER UN FAIT SUR UNE SALLE EST LA MÊME FAUTE QU'INVENTER UNE SALLE : dans
   les deux cas, la personne se déplace pour quelque chose qui n'existe pas.
   N'explique pas non plus POURQUOI une salle répond à la demande si le contexte
   ne le dit pas — contente-toi de la présenter.

Sois concret : nomme la salle, sa commune, sa capacité et son prix. Pas de formule
de politesse longue, pas de liste à puces, pas de titres, et pas d'appel au
contact pour finir.`;
}

// -----------------------------------------------------------------------------
// La validation du §8.5
// -----------------------------------------------------------------------------

type Verdict = { ok: boolean; fautes: string[] };

/// COMBIEN DE LETTRES DE CHAQUE ÉCRITURE, ET RIEN D'AUTRE.
///
/// Les chiffres, la ponctuation et les espaces ne disent la langue de personne :
/// « 300 » s'écrit pareil des deux côtés. Le latin-1 supplémentaire et le latin
/// étendu comptent avec l'alphabet latin — « é », « ï », « ç » sont des lettres
/// françaises, pas des symboles.
function comptesDEcriture(texte: string): { arabes: number; latines: number } {
  let arabes = 0;
  let latines = 0;
  for (const c of texte) {
    const code = c.codePointAt(0)!;
    if (code >= 0x0600 && code <= 0x06FF) arabes++;
    else if (
      (code >= 0x0041 && code <= 0x005A) || (code >= 0x0061 && code <= 0x007A) ||
      (code >= 0x00C0 && code <= 0x024F)
    ) latines++;
  }
  return { arabes, latines };
}

/// L'ÉCRITURE DE LA QUESTION SE COMPTE, ELLE NE SE DEMANDE PAS.
///
/// C'est ICI que se jouait la réponse française à une question arabe, et pas
/// dans la rédaction. « بغيت صالة في وهران عندها 300 كرسي » ne porte pas une
/// lettre latine ; le modèle l'a classée « mixte », et « mixte » veut dire
/// « réponds en français simple ». La consigne de rédaction était juste, et elle
/// a été suivie — sur une langue fausse. On ne corrige donc pas la rédaction :
/// on corrige ce qu'on lui donne à suivre.
///
/// UNE ÉCRITURE N'EST PAS UN JUGEMENT. Compter des lettres arabes est de la même
/// nature que comparer deux dates, et le §8.5 veut que ces choses-là se
/// tranchent ici, où elles ne peuvent pas changer d'un appel à l'autre. Elles en
/// changeaient : la même question, posée deux fois, revenait « mixte » puis
/// « ar ».
///
/// CE QUI RESTE AU MODÈLE EST LE SEUL VRAI JUGEMENT : séparer « fr » de
/// « mixte », c'est-à-dire le français du franco-arabe translittéré. Aucune
/// plage Unicode ne les sépare — « kayen salle f wahran » s'écrit dans le même
/// alphabet que « bonjour ».
function ecritureArabe(question: string): boolean {
  const { arabes, latines } = comptesDEcriture(question);
  return arabes > latines;
}

/// LA RÉPONSE SUIT LA LANGUE DE LA QUESTION, ET CE N'EST PLUS UNE CONSIGNE.
///
/// Elle l'a été jusqu'ici, et elle a échoué exactement comme échouent les
/// consignes : par intermittence. La question 15, en darja, a reçu une réponse
/// française au banc du J20 ; « بغيت صالة في وهران » en a reçu une au J21. Entre
/// les deux, la même question rendait parfois de l'arabe impeccable — ce qui est
/// pire qu'un échec franc, parce que rien ne le signale.
///
/// ON RETIRE D'ABORD LES NOMS PROPRES. La règle 9 impose d'écrire les salles et
/// les communes EN LATIN même au milieu d'une phrase arabe. Sans ce retrait, une
/// réponse arabe citant trois salles compterait des dizaines de lettres latines
/// parfaitement légitimes, et le contrôle accuserait une réponse juste.
///
/// « mixte » EST DU CÔTÉ LATIN : c'est le franco-arabe translittéré — « kayen
/// salle f wahran » —, et la règle 5 demande d'y répondre en français simple.
///
/// `langue` ARRIVE ICI COMPTÉE, pas déclarée — `ecritureArabe()` s'en est chargé
/// avant. C'est ce qui donne son sens à ce contrôle : juger la réponse sur une
/// langue que le modèle aurait lui-même choisie reviendrait à lui demander s'il
/// est d'accord avec lui-même.
function langueCorrespond(
  texte: string,
  langue: string,
  contexte: Salle[],
): boolean {
  // LE RETRAIT SE FAIT SUR LE TEXTE APLATI, des deux côtés. Le modèle écrit
  // parfois « Ain El Turck » là où la base porte « Aïn El Turck » : une
  // comparaison exacte ne retirerait rien, et les lettres latines d'un nom
  // propre compteraient contre une réponse arabe correcte. `aplatir()` ne touche
  // pas à l'arabe — ses lettres de base restent dans leur plage.
  let prose = aplatir(texte);
  for (const salle of contexte) {
    for (const nom of [salle.name, salle.commune, salle.wilaya_name]) {
      const plat = aplatir(nom ?? "");
      if (plat) prose = prose.split(plat).join(" ");
    }
  }

  const { arabes, latines } = comptesDEcriture(prose);

  // Une réponse sans aucune lettre ne dit rien de sa langue. On ne la condamne
  // pas là-dessus : les autres contrôles s'en chargeront.
  if (arabes + latines === 0) return true;

  return langue === "ar" ? arabes > latines : latines > arabes;
}

/// AUCUN APPEL À CONTACTER QUI QUE CE SOIT, ET SURTOUT PAS EN DIRECT.
///
/// « Contactez les propriétaires pour vérifier la disponibilité » — l'agent l'a
/// écrit, et c'est deux fautes en une phrase. C'est une invitation à CONTOURNER
/// la plateforme, et c'est contraire au §9 : le téléphone ne sort qu'après
/// acceptation de la demande, et il n'y a personne à joindre avant.
///
/// LA CAUSE ÉTAIT DANS LE PROMPT. L'ancienne règle 4 disait « le propriétaire
/// seul confirme » — le modèle en tirait obligeamment la conclusion qu'il
/// fallait aller le voir. La règle dit maintenant OÙ cela se passe : dans
/// l'application, en envoyant une demande depuis la fiche.
///
/// `appeler` ET `appelez`, MAIS PAS `appelée`. Les frontières de mot sont
/// indispensables ici : « une salle appelée El Bahia » est une phrase correcte,
/// et un motif trop large la condamnerait.
const APPEL_AU_CONTACT_FR =
  /\bcontact|\bjoindre\b|\bjoignez\b|\bappeler\b|\bappelez\b|telephon|\bnumero\b|coordonnees|renseignez[- ]vous/;

/// Les mêmes en arabe. `رقم` seul est écarté — il veut dire « numéro » au sens
/// large, et « رقم 300 » parlerait d'un nombre de chaises.
const APPEL_AU_CONTACT_AR = /اتصل|الاتصال|تواصل|هاتف/;

/// Rend la formule fautive, ou la chaîne vide.
function appelAuContact(texte: string): string {
  const latin = aplatir(texte).match(APPEL_AU_CONTACT_FR);
  if (latin) return latin[0];
  const arabe = texte.match(APPEL_AU_CONTACT_AR);
  if (arabe) return arabe[0];
  return "";
}

function validerLaReponse(
  texte: string,
  idsDeclares: string[],
  contexte: Salle[],
  catalogue: { id: string; name: string }[],
  langue: string,
): Verdict {
  const fautes: string[] = [];
  const idsDuContexte = new Set(contexte.map((s) => s.venue_id));

  // ------------------------------------------------------------------------
  // CONTRÔLE PRINCIPAL : LES IDENTIFIANTS. Il est le seul qui ne dépende ni de
  // la langue ni de l'écriture. Une réponse en arabe translitère les noms —
  // « قاعة ابن خلدون » pour Salle Ibn Khaldoun — et aucune comparaison de
  // chaînes latines ne les y retrouvera. C'est pour cela que le modèle doit
  // déclarer ce qu'il cite, et que le prompt en fait le champ le plus important.
  // ------------------------------------------------------------------------
  for (const id of idsDeclares) {
    if (!idsDuContexte.has(id)) fautes.push(`identifiant hors contexte : ${id}`);
  }

  // ------------------------------------------------------------------------
  // FILET SECONDAIRE : LES NOMS, EN ÉCRITURE LATINE SEULEMENT.
  //
  // Il attrape ce que la déclaration ne dit pas : une salle nommée dans la
  // prose sans que son identifiant soit déclaré. Il ne voit RIEN d'une réponse
  // en arabe, et ce n'est pas un oubli : écrire un détecteur de noms translitérés
  // demanderait de deviner comment un modèle rend « Chréa » en arabe, ce qui
  // serait une seconde source de vérité, plus fragile que celle qu'elle garde.
  //
  // Du nom le plus long au plus court, en effaçant ce qui est reconnu : sans
  // l'effacement, « Palais Dar El Feth » contiendrait « El Feth » et l'on
  // accuserait le modèle d'avoir cité une salle dont il n'a pas parlé.
  let reste = aplatir(texte);
  const parLongueur = [...catalogue].sort(
    (a, b) => coeurDuNom(b.name).length - coeurDuNom(a.name).length,
  );

  for (const salle of parLongueur) {
    const coeur = coeurDuNom(salle.name);
    if (!coeurUtilisable(coeur)) continue;

    // AUX FRONTIERES DE MOT : sans cela « el feth » se trouverait au milieu
    // d'un mot plus long, et « chrea » dans « chreabis ».
    const motif = new RegExp(`\\b${echapper(coeur)}\\b`, "g");
    if (!motif.test(reste)) continue;

    reste = reste.replace(new RegExp(`\\b${echapper(coeur)}\\b`, "g"), " ");
    if (!idsDuContexte.has(salle.id)) {
      fautes.push(`salle citée hors contexte : ${salle.name}`);
    }
  }

  // ------------------------------------------------------------------------
  // TROISIÈME CONTRÔLE : LA LANGUE. Voir `langueCorrespond()`.
  // ------------------------------------------------------------------------
  if (!langueCorrespond(texte, langue, contexte)) {
    fautes.push(`réponse hors de la langue attendue (${langue})`);
  }

  // ------------------------------------------------------------------------
  // QUATRIÈME CONTRÔLE : AUCUN APPEL AU CONTACT DIRECT (§9).
  // ------------------------------------------------------------------------
  const appel = appelAuContact(texte);
  if (appel) fautes.push(`appel au contact direct : « ${appel} »`);

  return { ok: fautes.length === 0, fautes };
}

/// La liste brute, quand le modèle a échoué deux fois. Pas de prose, pas
/// d'invention possible.
///
/// ELLE PORTE MAINTENANT UNE PHRASE D'INTRODUCTION, dans la langue de la
/// question. Sans elle, le repli d'une question arabe était un bloc entièrement
/// latin — noms, communes, nombres — sans un mot que son lecteur puisse lire. Le
/// corps reste latin, et c'est juste : la règle 9 veut que les noms propres
/// s'écrivent comme la base les porte.
///
/// ELLE NE CONTIENT AUCUN APPEL AU CONTACT, par construction : il n'y a pas de
/// prose où en glisser un. C'est ce qui en fait un repli sûr pour les deux
/// nouveaux contrôles autant que pour les deux anciens.
const LISTE_BRUTE_EN_TETE: Record<string, string> = {
  fr: "Voici les salles qui correspondent :",
  ar: "هذه القاعات اللي تقابل طلبك:",
  mixte: "Voici les salles qui correspondent :",
};

const AUCUNE_SALLE: Record<string, string> = {
  fr: "Aucune salle ne correspond à cette demande.",
  ar: "ما لقيت حتى قاعة تقابل هذا الطلب.",
  mixte: "Aucune salle ne correspond à cette demande.",
};

function listeBrute(salles: Salle[], langue: string): string {
  if (salles.length === 0) return AUCUNE_SALLE[langue] ?? AUCUNE_SALLE.fr;

  const lignes = salles.map((s) => {
    const prix = s.price != null ? ` — ${Math.round(Number(s.price))} DA` : "";
    return `${s.name}, ${s.commune} (${s.wilaya_name}) — ${s.capacity_seated} places${prix}`;
  });

  return [LISTE_BRUTE_EN_TETE[langue] ?? LISTE_BRUTE_EN_TETE.fr, ...lignes]
    .join("\n");
}

const HORS_SUJET: Record<string, string> = {
  fr: "Je ne m’occupe que des salles des fêtes : les trouver, les comparer et " +
    "expliquer comment les réserver. Je ne peux pas vous aider sur ce sujet.",
  ar: "أنا مختص فقط في قاعات الأفراح: البحث عنها ومقارنتها وشرح كيفية حجزها. " +
    "لا أستطيع مساعدتك في هذا الموضوع.",
  mixte: "Je ne m’occupe que des salles des fêtes : les trouver, les comparer " +
    "et expliquer comment les réserver. Je ne peux pas vous aider sur ce sujet.",
};

/// « 2027-08-01 » devient « 1er août 2027 ».
const MOIS_FR = [
  "janvier", "février", "mars", "avril", "mai", "juin",
  "juillet", "août", "septembre", "octobre", "novembre", "décembre",
];

function dateEnClair(iso: string): string {
  const [a, m, j] = iso.split("-").map(Number);
  const jour = j === 1 ? "1er" : String(j);
  return `${jour} ${MOIS_FR[m - 1]} ${a}`;
}

/// L'ANNONCE DE L'HYPOTHÈSE NE PASSE PAS PAR LE MODÈLE.
///
/// Elle y passait, avec un exemple dans le prompt — et le modèle recopiait la
/// date de l'exemple au lieu de celle qu'il venait d'utiliser. Il annonçait
/// « je pars sur le 14 août » en chiffrant le 1er : une phrase fausse sur un
/// point où l'utilisateur va réserver.
///
/// C'est une affirmation FACTUELLE, comme la comparaison de dates plus haut :
/// elle se construit ici, où la date est connue, et rien ne peut la déformer.
/// `jour` est vide quand seule l'année manquait, et porte le jour de la semaine
/// quand c'est lui qui a fixé la date — on ne dit pas « une autre année » à
/// quelqu'un qui avait demandé un samedi.
function phraseAnneeSupposee(date: string, langue: string, jour: string): string {
  if (jour) {
    if (langue === "ar") {
      return `أنطلق من ${JOURS_AR[jour] ?? ""} ${date} — أخبرني إن كنت تقصد تاريخاً آخر. `;
    }
    return `Je pars sur le ${jour} ${dateEnClair(date)} — dites-moi si vous pensiez à une autre date. `;
  }
  if (langue === "ar") {
    return `أنطلق من تاريخ ${date} — أخبرني إن كنت تقصد سنة أخرى. `;
  }
  return `Je pars sur le ${dateEnClair(date)} — dites-moi si vous pensiez à une autre année. `;
}

const DATE_PASSEE: Record<string, string> = {
  fr: "Cette date est déjà passée. Indiquez-moi une date à venir et je vous " +
    "dirai quelles salles sont libres.",
  ar: "هذا التاريخ قد مضى. أعطني تاريخاً قادماً وسأخبرك بالقاعات المتوفرة.",
  mixte: "Cette date est déjà passée. Donnez-moi une date à venir et je vous " +
    "dirai quelles salles sont libres.",
};

// -----------------------------------------------------------------------------

Deno.serve(async (requete: Request): Promise<Response> => {
  // Le pré-vol du navigateur. Sans lui, l'appel depuis l'écran 8 n'a même pas
  // lieu — voir ENTETES_CORS.
  if (requete.method === "OPTIONS") {
    return new Response("ok", { headers: ENTETES_CORS });
  }

  if (requete.method !== "POST") {
    return reponseHttp({ message: "Cette fonction ne répond qu'en POST." }, 405);
  }

  const cleGemini = Deno.env.get("GEMINI_API_KEY");
  const modele = Deno.env.get("GEMINI_MODEL") || MODELE_PAR_DEFAUT;
  const serviceUrl = Deno.env.get("EMBEDDINGS_URL");
  const jetonEmbed = Deno.env.get("EMBED_TOKEN");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const cleService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!cleGemini || !serviceUrl || !jetonEmbed || !supabaseUrl || !cleService) {
    console.error(
      "Configuration incomplète — GEMINI_API_KEY:" + Boolean(cleGemini) +
        " EMBEDDINGS_URL:" + Boolean(serviceUrl) +
        " EMBED_TOKEN:" + Boolean(jetonEmbed),
    );
    return reponseHttp({ message: "Agent non configuré." }, 500);
  }

  let question = "";
  try {
    const corps = await requete.json();
    question = String(corps?.question ?? "").trim();
  } catch {
    return reponseHttp({ message: "Corps illisible." }, 400);
  }

  if (!question) {
    return reponseHttp({ message: "Question vide." }, 400);
  }

  const debut = Date.now();
  let criteres: Criteres | null = null;
  let langue = "fr";
  let rejeux = 0;

  /// Journalise sans jamais faire échouer la réponse (§8.5).
  const journaliser = async (
    statut: string,
    ids: string[],
    nbCandidats: number | null,
  ) => {
    try {
      await rpc(supabaseUrl, cleService, "journaliser_conversation", {
        p_question: question,
        p_langue: langue,
        p_criteres: criteres,
        p_venue_ids: ids,
        p_nb_candidats: nbCandidats,
        p_rejeux: rejeux,
        p_duree_ms: Date.now() - debut,
        p_modele: modele,
        p_statut: statut,
      });
    } catch (erreur) {
      console.error("Journal impossible :", erreur);
    }
  };

  try {
    // -------------------------------------------------------------------------
    // 1. Extraire les critères.
    // -------------------------------------------------------------------------
    const aujourdHui = new Date().toISOString().slice(0, 10);
    const brut = await demanderAuModele(
      cleGemini, modele, instructionExtraction(aujourdHui),
      question, SCHEMA_CRITERES,
    );

    // On retraduit ici les chaînes vides et les zéros en « non renseigné », et
    // on jette tout ce qui n'est pas dans les vocabulaires de la base : un code
    // inventé ne filtrerait rien, silencieusement.
    const equipements = (Array.isArray(brut.equipements) ? brut.equipements : [])
      .map(String).filter((c) => EQUIPEMENTS.includes(c));

    criteres = {
      hors_sujet: brut.hors_sujet === true,
      question_procedure: brut.question_procedure === true,
      langue: ["fr", "ar", "mixte"].includes(String(brut.langue))
        ? String(brut.langue) : "fr",
      date_origine: ["aucune", "explicite", "annee_absente", "relative"]
        .includes(String(brut.date_origine))
        ? String(brut.date_origine) : "aucune",
      annee_supposee: false,
      wilaya_code: /^\d{2}$/.test(String(brut.wilaya_code ?? ""))
        ? String(brut.wilaya_code) : "",
      commune: String(brut.commune ?? "").trim(),
      date: /^\d{4}-\d{2}-\d{2}$/.test(String(brut.date ?? ""))
        ? String(brut.date) : "",
      creneau: CRENEAUX.includes(String(brut.creneau)) ? String(brut.creneau) : "",
      invites: Number(brut.invites) > 0 ? Math.round(Number(brut.invites)) : 0,
      budget_max: Number(brut.budget_max) > 0
        ? Math.round(Number(brut.budget_max)) : 0,
      type_evenement: TYPES_EVENEMENT.includes(String(brut.type_evenement))
        ? String(brut.type_evenement) : "",
      equipements,
      jour_semaine: JOURS_SEMAINE.includes(String(brut.jour_semaine))
        ? String(brut.jour_semaine) : "",
      jour_impose: false,
      parking_min: Number(brut.parking_min) > 0
        ? Math.round(Number(brut.parking_min)) : 0,
      parking_flou: brut.parking_flou === true,
      prix_bas: brut.prix_bas === true,
      soft_query: String(brut.soft_query ?? "").trim(),
    };

    // L'ÉCRITURE TRANCHE, LE MODÈLE GARDE LE RESTE — voir `ecritureArabe()`.
    //
    // Une question écrite en caractères arabes est en arabe, quoi que le modèle
    // en ait dit ; une question sans un seul caractère arabe n'est pas en arabe,
    // quoi qu'il en ait dit non plus. Dans ce second cas, c'est « mixte » qui
    // reprend la main et non « fr » : le modèle a entendu de l'arabe quelque
    // part, et du darja écrit en lettres latines est exactement ce que « mixte »
    // désigne. Les deux se répondent en français simple, donc l'erreur, s'il y
    // en a une, ne coûte rien à personne.
    criteres.langue = ecritureArabe(question)
      ? "ar"
      : criteres.langue === "ar"
      ? "mixte"
      : criteres.langue;
    langue = criteres.langue;

    // -------------------------------------------------------------------------
    // 2. Les deux sorties qui ne demandent aucune salle.
    // -------------------------------------------------------------------------
    if (criteres.hors_sujet) {
      await journaliser("hors_sujet", [], null);
      return reponseHttp({
        reponse: HORS_SUJET[langue] ?? HORS_SUJET.fr,
        salles: [], criteres, modele, statut: "hors_sujet",
      });
    }

    // UNE QUESTION DE PROCÉDURE NE CHERCHE AUCUNE SALLE. On ne fait donc ni
    // empreinte ni requête : le modèle reçoit le texte du parcours, un contexte
    // VIDE, et la validation du §8.5 garantit qu'il ne nommera personne —
    // toute salle citée serait hors contexte, et ferait rejouer.
    if (criteres.question_procedure) {
      // LES QUATRE REPÈRES SE VÉRIFIENT, ILS NE SE DEMANDENT PAS.
      //
      // Le modèle reformulait le parcours et perdait l'option de 72 heures —
      // le délai au bout duquel la date se relâche. On relit donc sa réponse,
      // et si un repère manque on rejoue ; s'il manque encore, c'est le texte
      // de référence qui part, mot pour mot, dans la langue de la question.
      // Moins fluide, et juste.
      const texteDeReference = langue === "ar" ? PROCEDURE_AR : PROCEDURE;
      let texteProc = "";

      for (let essai = 0; essai <= REJEUX_MAX; essai++) {
        const sortie = await demanderAuModele(
          cleGemini, modele, instructionRedaction(),
          JSON.stringify({
            question,
            langue_attendue: langue,
            texte_de_procedure: texteDeReference,
            salles_disponibles: [],
          }),
          SCHEMA_REPONSE,
        );
        const candidat = String(sortie.reponse ?? "").trim();

        // LES TROIS MÊMES EXIGENCES QU'AILLEURS. Une réponse de procédure a ses
        // quatre repères à porter, mais elle doit aussi être dans la langue de
        // la question — et ne renvoyer vers personne. « Appelez la salle pour
        // bloquer une date » serait une réponse complète et fausse.
        //
        // Le contexte est VIDE ici : aucun nom propre à retirer avant de
        // compter les lettres, et c'est bien ce que `langueCorrespond` reçoit.
        const manque = !procedureComplete(candidat)
          ? "repère manquant"
          : !langueCorrespond(candidat, langue, [])
          ? `hors de la langue attendue (${langue})`
          : appelAuContact(candidat)
          ? `appel au contact direct : « ${appelAuContact(candidat)} »`
          : "";

        if (!manque) {
          texteProc = candidat;
          break;
        }
        console.error(`Procédure rejetée (essai ${essai + 1}) : ${manque}.`);
        rejeux = essai + 1;
      }

      if (!texteProc) texteProc = texteDeReference;
      await journaliser("procedure", [], null);
      return reponseHttp({
        reponse: texteProc,
        salles: [], criteres, modele, statut: "procedure",
      });
    }

    // L'ANNÉE MANQUANTE SE RÈGLE AVANT LE TEST DE DATE PASSÉE, et seulement
    // quand la question ne la donnait pas. « hier » reste hier ; « le 14 août »
    // devient le prochain 14 août. La différence tient dans `date_origine`, que
    // le modèle renseigne — c'est la seule chose qu'on lui demande ici, et c'est
    // une observation, pas un calcul.
    if (criteres.date && criteres.date_origine === "annee_absente") {
      criteres.date = avancerJusquAVenir(criteres.date, aujourdHui);
      // L'HYPOTHÈSE TIENT À L'ABSENCE DE L'ANNÉE, PAS À NOTRE CORRECTION. Le
      // modèle choisit parfois déjà la bonne année — il n'y a alors rien à
      // avancer, et l'on se taisait. Mais l'utilisateur n'a toujours pas dit
      // « 2027 » : c'est nous qui l'avons décidé pour lui, et il doit pouvoir
      // nous reprendre.
      criteres.annee_supposee = true;
    }

    // LE JOUR DE LA SEMAINE FIXE LA DATE, et il la fixe APRÈS le report d'année.
    //
    // « un samedi soir en août » : le modèle a rendu le 1er août, l'année a été
    // avancée si besoin, et c'est seulement maintenant qu'on cherche le premier
    // samedi À VENIR de ce mois-là. Le mois vient de la question, le jour de la
    // semaine aussi ; le quantième, lui, n'a jamais été demandé par personne.
    //
    // ON NE TOUCHE À RIEN quand la date est explicite ou relative : qui écrit
    // « le 14 août 2027 » a tranché, et « hier » ne se déplace pas jusqu'au
    // samedi précédent.
    if (
      criteres.jour_semaine &&
      (criteres.date_origine === "annee_absente" ||
        criteres.date_origine === "aucune")
    ) {
      const mois = criteres.date ? Number(criteres.date.slice(5, 7)) : null;
      const trouvee = prochaineDateAuJour(criteres.jour_semaine, aujourdHui, mois);
      if (trouvee) {
        criteres.date = trouvee;
        criteres.jour_impose = true;
        // On a choisi une date que la personne n'a pas donnée : elle doit
        // pouvoir nous reprendre, comme pour l'année.
        criteres.annee_supposee = true;
      }
    }

    // LA DATE PASSÉE SE TRANCHE ICI, pas par le modèle. C'est une comparaison
    // de dates : la confier à un modèle de langage, c'est accepter qu'il se
    // trompe une fois sur vingt sur quelque chose qui ne se discute pas.
    if (criteres.date && criteres.date < aujourdHui) {
      await journaliser("date_passee", [], null);
      return reponseHttp({
        reponse: DATE_PASSEE[langue] ?? DATE_PASSEE.fr,
        salles: [], criteres, modele, statut: "date_passee",
      });
    }

    // -------------------------------------------------------------------------
    // 3. Vectoriser la partie floue.
    //
    // On envoie `soft_query` quand le modèle en a dégagé une — c'est ce que
    // demande le §8.1 — et la question entière sinon. Le service pose lui-même
    // le préfixe « query: ».
    //
    // SI LE SERVICE NE RÉPOND PAS, ON CONTINUE SANS VECTEUR. Le tri exact suffit
    // à répondre ; on perd le classement fin, pas la réponse.
    // -------------------------------------------------------------------------
    let vecteur: string | null = null;
    // Le nom du modele d'empreintes, pour ne comparer qu'a des vecteurs de la
    // meme famille. Null quand le service n'a pas repondu.
    let modeleEmpreintes: string | null = null;
    const aVectoriser = criteres.soft_query || question;
    try {
      const sante = await fetch(`${serviceUrl}/health`, {
        signal: AbortSignal.timeout(DELAI_EMPREINTES_MS),
      });
      if (!sante.ok) throw new Error(`/health a rendu ${sante.status}`);
      const etat = await sante.json();

      const appel = await fetch(`${serviceUrl}/embed`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${jetonEmbed}`,
        },
        body: JSON.stringify({ textes: [aVectoriser], nature: "question" }),
        signal: AbortSignal.timeout(DELAI_EMPREINTES_MS),
      });
      if (!appel.ok) throw new Error(`/embed a rendu ${appel.status}`);

      const resultat = await appel.json();
      if (String(resultat?.modele) !== String(etat?.modele)) {
        throw new Error("le service a changé de modèle en cours de route");
      }
      vecteur = `[${(resultat.vecteurs[0] as number[]).join(",")}]`;
      modeleEmpreintes = String(etat.modele);
    } catch (erreur) {
      console.error("Empreinte indisponible, on continue sans :", erreur);
      vecteur = null;
      modeleEmpreintes = null;
    }

    // -------------------------------------------------------------------------
    // 4. Le tri exact, puis le classement.
    // -------------------------------------------------------------------------
    const salles = (await rpc(supabaseUrl, cleService, "salles_pour_agent", {
      p_embedding: vecteur,
      p_model: modeleEmpreintes,
      p_wilaya_code: criteres.wilaya_code || null,
      p_commune: criteres.commune || null,
      p_event_date: criteres.date || null,
      p_slot: criteres.creneau || null,
      p_guest_count: criteres.invites || null,
      p_max_budget: criteres.budget_max || null,
      p_event_type: criteres.type_evenement || null,
      p_amenities: criteres.equipements.length ? criteres.equipements : null,
      // UNE EXIGENCE CHIFFRÉE SE FILTRE ; UNE PRÉFÉRENCE CLASSE.
      //
      // « au moins 100 places » retire les salles trop petites ; « beaucoup de
      // parking » ne retire rien et remonte les plus grandes. Le §8.1 le dit
      // autrement : la similarité ne sait pas compter, alors on ne lui confie
      // plus les nombres.
      p_parking_min: criteres.parking_min || null,
      // LE PRIX L'EMPORTE SUR LE PARKING quand les deux sont demandés : « la
      // moins chère » est un superlatif, il désigne UNE salle, et un tri par
      // parking la ferait disparaître au milieu de la liste.
      p_ordre: criteres.prix_bas ? "prix" : (criteres.parking_flou ? "parking" : null),
      // TROIS, ET NON CINQ, QUAND ON DEMANDE LE MOINS CHER. Citer cinq salles
      // classées par prix, c'est répondre « voici la moins chère, et voici
      // quatre plus chères » : la quatrième dessert la réponse.
      p_limit: criteres.prix_bas ? SALLES_PRIX_BAS : SALLES_MAX,
    })) as Salle[];

    // -------------------------------------------------------------------------
    // 5. Rédiger, valider, rejouer si besoin.
    // -------------------------------------------------------------------------
    // DEUX OBJETS LÀ OÙ IL Y EN AVAIT UN, et c'est tout ce que la photo a
    // changé. `contexte` est ce que le MODÈLE lit ; `pourLApplication` est ce
    // que l'écran 8 reçoit — le même, plus la photo de la carte.
    //
    // Le §8.5 tient parce que le contexte est PAUVRE : chaque champ ajouté est
    // de la matière à reformuler, et à déborder. Un chemin de Storage n'aide
    // pas à rédiger trois phrases.
    const contexte = salles.map((s) => ({
      venue_id: s.venue_id,
      nom: s.name,
      commune: s.commune,
      wilaya: s.wilaya_name,
      wilaya_ar: s.wilaya_name_ar,
      capacite: s.capacity_seated,
      parking: s.parking_spaces,
      equipements: s.amenity_codes,
      prix_da: s.price == null ? null : Math.round(Number(s.price)),
      creneau_du_prix: s.price_slot,
      note: s.rating == null ? null : Number(s.rating),
      nombre_avis: s.review_count,
    }));

    const pourLApplication = salles.map((s, i) => ({
      ...contexte[i],
      photo: s.cover_photo,
    }));

    const entree = JSON.stringify({
      question,
      langue_attendue: langue,
      criteres_compris: criteres,
      salles_disponibles: contexte,
    });

    const tousLesNoms = await nomsDuCatalogue(supabaseUrl, cleService);

    let texte = "";
    let ids: string[] = [];
    let statut = salles.length === 0 ? "aucune_salle" : "ok";

    for (let essai = 0; essai <= REJEUX_MAX; essai++) {
      const sortie = await demanderAuModele(
        cleGemini, modele, instructionRedaction(), entree, SCHEMA_REPONSE,
      );
      texte = String(sortie.reponse ?? "").trim();
      ids = (Array.isArray(sortie.venue_ids) ? sortie.venue_ids : []).map(String);

      const verdict = validerLaReponse(texte, ids, salles, tousLesNoms, langue);
      if (verdict.ok) break;

      console.error(`Réponse rejetée (essai ${essai + 1}) :`, verdict.fautes);
      rejeux = essai + 1;

      if (essai === REJEUX_MAX) {
        // Deuxième échec : la liste brute, sans phrase rédigée. Elle est dans la
        // langue de la question par son en-tête, et sans appel au contact par
        // construction — les quatre contrôles y passent sans qu'on ait à les
        // rejouer dessus.
        texte = listeBrute(salles, langue);
        ids = salles.map((s) => s.venue_id);
        statut = "liste_brute";
      }
    }

    // L'hypothèse d'abord, la réponse ensuite — et seulement sur une réponse
    // rédigée : une liste brute n'a pas de première phrase où la glisser.
    if (criteres.annee_supposee && statut !== "liste_brute") {
      texte = phraseAnneeSupposee(
        criteres.date,
        langue,
        criteres.jour_impose ? criteres.jour_semaine : "",
      ) + texte;
    }

    await journaliser(statut, ids, salles.length);

    return reponseHttp({
      reponse: texte,
      salles: pourLApplication,
      criteres,
      modele,
      rejeux,
      statut,
      duree_ms: Date.now() - debut,
    });
  } catch (erreur) {
    if (erreur instanceof QuotaEpuise) {
      await journaliser("quota", [], null);
      // UNE PHRASE, PAS UNE TRACE. 200 et non 429 : côté application, ce n'est
      // pas une panne à réessayer en boucle, c'est une réponse à afficher.
      return reponseHttp({
        reponse: langue === "ar"
          ? "المساعد مشغول حالياً. حاول مرة أخرى بعد دقيقة، أو استعمل البحث العادي."
          : "L’assistant est très sollicité en ce moment. Réessayez dans une " +
            "minute, ou utilisez la recherche classique.",
        salles: [], criteres, modele, statut: "quota",
      });
    }

    console.error("ai-chat :", erreur);
    await journaliser("erreur", [], null);
    return reponseHttp({ message: "L'assistant n'a pas pu répondre." }, 500);
  }
});

/// Tous les noms de salle de la base, brouillons compris.
async function nomsDuCatalogue(
  url: string,
  cle: string,
): Promise<{ id: string; name: string }[]> {
  const appel = await fetch(`${url}/rest/v1/venues?select=id,name`, {
    headers: { apikey: cle, Authorization: `Bearer ${cle}` },
  });
  if (!appel.ok) return [];
  return await appel.json();
}
