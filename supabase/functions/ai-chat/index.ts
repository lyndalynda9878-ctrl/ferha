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
// LA LIGNE DE PARTAGE EST AU §8.1 : « la similarité ne sait pas compter ».
// Elle rapprochera « 300 personnes » de « 250 personnes » et proposera une
// salle déjà réservée. On ne lui confie donc jamais un chiffre — seulement le
// flou : « moderne », « avec un jardin », « près de la mer ».
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
// LES GARDE-FOUS (§8.5), ET CE QU'ILS COÛTENT
//
// TOUTE SALLE CITÉE HORS CONTEXTE FAIT REJOUER. On vérifie deux choses : les
// identifiants que le modèle déclare, et les NOMS qu'il écrit dans sa prose —
// car c'est par le nom qu'une salle inventée arrive chez l'utilisateur, pas par
// un UUID. Le balayage se fait du nom le plus long au plus court, en effaçant
// au passage ce qui a déjà été reconnu : sans cela, « Palais Dar El Feth »
// contient « El Feth » et l'on accuserait le modèle d'avoir cité une salle
// dont il n'a jamais parlé.
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
// et la validation des noms porte sur le catalogue ENTIER — brouillons
// compris. Citer « Espace Nour El Houda » fait donc rejouer, alors même que
// cette salle n'a jamais été dans aucun contexte.
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

/// Combien de salles le modèle voit. Huit, comme au §8.1 : assez pour choisir,
/// assez peu pour que la réponse reste lisible.
const SALLES_MAX = 8;

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
    langue: { type: "string", enum: ["fr", "ar", "mixte"] },
    wilaya_code: { type: "string" },
    commune: { type: "string" },
    date: { type: "string" },
    creneau: { type: "string" },
    invites: { type: "integer" },
    budget_max: { type: "integer" },
    type_evenement: { type: "string" },
    equipements: { type: "array", items: { type: "string" } },
    soft_query: { type: "string" },
  },
  required: ["hors_sujet", "langue", "equipements", "soft_query"],
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
  langue: string;
  wilaya_code: string;
  commune: string;
  date: string;
  creneau: string;
  invites: number;
  budget_max: number;
  type_evenement: string;
  equipements: string[];
  soft_query: string;
};

type Salle = {
  venue_id: string;
  name: string;
  commune: string;
  wilaya_name: string;
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
    headers: { "Content-Type": "application/json" },
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
- langue : "fr" si la question est en français, "ar" si elle est en caractères arabes,
  "mixte" si elle mélange le français et l'arabe translittéré.
- wilaya_code : le code à deux chiffres, depuis cette liste : ${WILAYAS}.
  Chaîne vide si aucune wilaya n'est nommée. Reconnais les noms en arabe
  (وهران = 31, الجزائر = 16, سطيف = 19, قسنطينة = 25, البليدة = 09)
  et les translittérations (wahran, alger, setif, constantine, blida, tizi ouzou).
  Une COMMUNE citée sans wilaya (Chéraga, Zéralda, Boufarik, Birtouta, El Khroub,
  Aïn El Turck, Bir El Djir, Ouled Yaïch) va dans "commune", pas dans wilaya_code.
- commune : le nom de la commune si la question en cite une. Chaîne vide sinon.
- date : "AAAA-MM-JJ" si la question donne une date, même relative ("demain", "hier",
  "le 14 août"). Si l'année manque, prends la prochaine occurrence à venir.
  Chaîne vide si aucune date.
- creneau : "midi", "soir" ou "journee". Chaîne vide si non précisé.
- invites : le nombre de personnes attendues. 0 si non précisé.
- budget_max : le budget maximum en dinars, en nombre entier. 0 si non précisé.
- type_evenement : un seul parmi ${TYPES_EVENEMENT.join(", ")}. Chaîne vide sinon.
  "عرس" et "3ors" = mariage. "عقيقة" et "aqiqa" = circoncision.
- equipements : les codes demandés, uniquement parmi ${EQUIPEMENTS.join(", ")}.
  Tableau vide si aucun. "parking" n'est PAS un équipement : c'est une capacité
  chiffrée, mets-la dans soft_query.
- soft_query : ce qui reste et qui ne se filtre pas — l'ambiance, la proximité de
  la mer, un grand parking, le prix bas. Reformule-le en quelques mots dans la
  langue de la question. Chaîne vide s'il n'y a rien de tel.

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
   (wilaya sans salle, capacité trop grande, budget trop bas). Ne propose RIEN d'autre.
4. Tu ne promets aucune disponibilité : le propriétaire seul confirme.
5. Réponds dans la LANGUE DE LA QUESTION. Si elle est en arabe, réponds en arabe.
   Si elle mélange français et arabe translittéré, réponds en français simple.
6. venue_ids doit contenir, dans l'ordre où tu les cites, les identifiants exacts
   des salles dont tu parles — et eux seuls.

Sois concret : nomme la salle, sa commune, sa capacité et son prix. Pas de formule
de politesse longue, pas de liste à puces, pas de titres.`;
}

// -----------------------------------------------------------------------------
// La validation du §8.5
// -----------------------------------------------------------------------------

type Verdict = { ok: boolean; fautes: string[] };

function validerLaReponse(
  texte: string,
  idsDeclares: string[],
  contexte: Salle[],
  catalogue: { id: string; name: string }[],
): Verdict {
  const fautes: string[] = [];
  const idsDuContexte = new Set(contexte.map((s) => s.venue_id));

  for (const id of idsDeclares) {
    if (!idsDuContexte.has(id)) fautes.push(`identifiant hors contexte : ${id}`);
  }

  // LES NOMS, du plus long au plus court, en effaçant ce qui est reconnu. Sans
  // l'effacement, « Palais Dar El Feth » contiendrait « El Feth » et l'on
  // accuserait le modèle d'avoir cité une salle dont il n'a pas parlé.
  let reste = aplatir(texte);
  const parLongueur = [...catalogue].sort(
    (a, b) => coeurDuNom(b.name).length - coeurDuNom(a.name).length,
  );

  for (const salle of parLongueur) {
    const coeur = coeurDuNom(salle.name);
    if (!coeur || !reste.includes(coeur)) continue;

    reste = reste.split(coeur).join(" ");
    if (!idsDuContexte.has(salle.id)) {
      fautes.push(`salle citée hors contexte : ${salle.name}`);
    }
  }

  return { ok: fautes.length === 0, fautes };
}

/// La liste brute, quand le modèle a échoué deux fois. Pas de prose, pas
/// d'invention possible.
function listeBrute(salles: Salle[]): string {
  if (salles.length === 0) return "Aucune salle ne correspond à cette demande.";
  return salles
    .map((s) => {
      const prix = s.price != null ? ` — ${Math.round(Number(s.price))} DA` : "";
      return `${s.name}, ${s.commune} (${s.wilaya_name}) — ${s.capacity_seated} places${prix}`;
    })
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

const DATE_PASSEE: Record<string, string> = {
  fr: "Cette date est déjà passée. Indiquez-moi une date à venir et je vous " +
    "dirai quelles salles sont libres.",
  ar: "هذا التاريخ قد مضى. أعطني تاريخاً قادماً وسأخبرك بالقاعات المتوفرة.",
  mixte: "Cette date est déjà passée. Donnez-moi une date à venir et je vous " +
    "dirai quelles salles sont libres.",
};

// -----------------------------------------------------------------------------

Deno.serve(async (requete: Request): Promise<Response> => {
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
      langue: ["fr", "ar", "mixte"].includes(String(brut.langue))
        ? String(brut.langue) : "fr",
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
      soft_query: String(brut.soft_query ?? "").trim(),
    };
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
      p_limit: SALLES_MAX,
    })) as Salle[];

    // -------------------------------------------------------------------------
    // 5. Rédiger, valider, rejouer si besoin.
    // -------------------------------------------------------------------------
    const contexte = salles.map((s) => ({
      venue_id: s.venue_id,
      nom: s.name,
      commune: s.commune,
      wilaya: s.wilaya_name,
      capacite: s.capacity_seated,
      parking: s.parking_spaces,
      equipements: s.amenity_codes,
      prix_da: s.price == null ? null : Math.round(Number(s.price)),
      creneau_du_prix: s.price_slot,
      note: s.rating == null ? null : Number(s.rating),
      nombre_avis: s.review_count,
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

      const verdict = validerLaReponse(texte, ids, salles, tousLesNoms);
      if (verdict.ok) break;

      console.error(`Réponse rejetée (essai ${essai + 1}) :`, verdict.fautes);
      rejeux = essai + 1;

      if (essai === REJEUX_MAX) {
        // Deuxième échec : la liste brute, sans phrase rédigée.
        texte = listeBrute(salles);
        ids = salles.map((s) => s.venue_id);
        statut = "liste_brute";
      }
    }

    await journaliser(statut, ids, salles.length);

    return reponseHttp({
      reponse: texte,
      salles: contexte,
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
