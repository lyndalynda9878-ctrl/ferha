// =============================================================================
// Ferha — Edge Function « summarize-reviews » (§8.2 ; §7.2)
//
// La synthèse des avis. Le deuxième des quatre usages du §8, et le seul qui ne
// soit PAS du RAG : « tous les avis tiennent dans le contexte. Résumé
// pré-calculé la nuit et stocké. » Il n'y a rien à chercher, rien à classer —
// on lit les avis d'UNE salle, et on les résume.
//
// TROIS TEMPS, ET LE SQL EN FAIT DEUX :
//
//   1. Le SQL dit QUI est à refaire — `avis_pour_synthese()`. Publiée, au moins
//      trois avis porteurs de texte, et un hachage différent de la dernière fois.
//   2. Le MODÈLE rédige, à partir du texte des avis et de rien d'autre.
//   3. Le SQL ACCEPTE ou refuse — `enregistrer_synthese_avis()`, qui revérifie
//      les deux règles.
//
// CETTE FONCTION NE CONNAÎT AUCUNE RÈGLE MÉTIER. Ni « publiée », ni « trois
// avis », ni « a changé ». Elle transporte. C'est la même division du travail
// qu'« embed-venue » avec `salles_a_indexer()`, et elle a la même raison : une
// règle écrite ici serait un second gardien, qui finirait par diverger.
//
// =============================================================================
// CE QUE LE MODÈLE NE PEUT PAS FAIRE, PARCE QU'IL NE LE VOIT PAS
//
// IL NE VOIT AUCUN NOM DE CLIENT. `avis_pour_synthese()` rend la note, la date
// et le corps de chaque avis — jamais l'auteur, pas même abrégé. Il ne peut donc
// pas écrire « Sarah B. a trouvé la salle froide ». Ce n'est pas une consigne,
// c'est une absence : le §8.5 préfère une donnée absente à un garde-fou, et un
// garde-fou à une consigne.
//
// IL NE VOIT AUCUNE NOTE MOYENNE, aucun compte, aucun prix. La note bayésienne
// s'affiche juste au-dessus du bloc de synthèse, calculée par `venue_ratings` ;
// une seconde note écrite en toutes lettres dans la prose serait une seconde
// source de vérité, et c'est exactement ce que le projet interdit pour le prix.
//
// =============================================================================
// LES DEUX GARDE-FOUS MÉCANIQUES
//
// 1. AUCUN CHIFFRE QUI NE SOIT DANS LES AVIS. Chaque suite de chiffres de la
//    synthèse est cherchée dans le texte des avis réunis. « 4,6 sur 5 »,
//    « 34 avis », « jugé lent par 4 clients » : aucun de ces nombres n'est
//    écrit par un client, tous seraient des calculs — et « aucune note
//    recalculée » est la règle. C'est un contrôle qui ne dépend ni de la langue
//    ni de l'écriture, comme la déclaration d'identifiants de l'agent.
//
//    (La maquette écrit « par 4 clients sur les mariages de plus de 350
//    invités ». C'est un dessin, pas une promesse : ce 4-là est un comptage que
//    le modèle ferait de tête, et il le ferait faux une fois sur cinq.)
//
// 2. UNE RÉSERVE QUAND LA BASE EN CONNAÎT UNE. « Un résumé exclusivement
//    flatteur n'est pas cru » (maquettes, écran 7). Le SQL compte les avis à
//    trois étoiles ou moins — `notes_basses`, un FAIT — et quand il y en a, la
//    synthèse doit déclarer au moins une réserve. Sinon on rejoue ; au second
//    échec, on n'écrit RIEN : l'ancienne synthèse reste, et la salle repassera
//    demain. Une synthèse muette sur ce que les clients ont reproché est pire
//    que pas de synthèse.
//
// CE QUE CELA NE GARANTIT PAS, et il faut le dire comme l'ai-chat le dit de sa
// règle 10 : que la réserve DÉCLARÉE soit bien celle des avis, et qu'aucun fait
// ne soit inventé. Vérifier une prose libre contre son contexte demanderait un
// second modèle, qui se tromperait aussi. Ce qui tient la règle ici, c'est que
// le contexte est PAUVRE — quelques phrases de clients, et rien d'autre.
//
// =============================================================================
// LA LANGUE DE LA SYNTHÈSE EST CELLE DES AVIS
//
// Une seule synthèse est stockée, et le quota gratuit interdit d'en écrire deux.
// Elle est donc rédigée dans la langue majoritaire des avis qu'elle résume — et
// ces avis-là sont juste en dessous, dans la même langue. Un lecteur qui lit les
// avis lit la synthèse.
//
// L'application n'a rien à savoir de cette langue : elle détecte le sens
// d'écriture du texte lui-même, comme pour la réponse de l'agent.
//
// =============================================================================
// QUI A LE DROIT D'APPELER
//
// `verify_jwt` = true : la passerelle Supabase vérifie d'abord que la clé
// présentée appartient bien à ce projet. Cela ne suffit pas : la clé PUBLIQUE
// en fait partie, et elle part dans le bundle web. Sans contrôle de plus,
// n'importe qui pourrait réveiller cette fonction en boucle et vider le quota
// gratuit d'une nuit.
//
// ON COMPARE DONC LE JETON À LA CLÉ DE SERVICE que la plateforme nous donne
// déjà, et c'est le contrôle qui marche avec LES DEUX SYSTÈMES DE CLÉS de
// Supabase — l'ancien, où la clé de service est un JWT portant
// `role: service_role`, et le nouveau, où c'est une chaîne opaque
// `sb_secret_…` qui ne se décode pas. Ce projet est du second genre : sa clé
// publique est un `sb_publishable_…`, et un contrôle qui ne saurait lire qu'une
// revendication `role` aurait fermé la porte au cron lui-même.
//
// CONSÉQUENCE POUR LE VAULT : METTEZ-Y LA CLÉ `service_role` EN `eyJ…`, celle
// du système ancien, tant que ce projet l'a encore active.
//
// Elle passe par le SECOND chemin — un JWT dont le rôle est `service_role` —
// et ce chemin ne dépend pas de ce que la plateforme a mis dans
// `SUPABASE_SERVICE_ROLE_KEY` : il lit la revendication, un point c'est tout.
// Une clé `sb_secret_…`, elle, ne passerait que par l'égalité exacte, donc
// seulement si la plateforme nous donne cette forme-là — et on ne peut pas le
// savoir depuis ici sans faire fuir le secret.
//
// Le jour où les clés anciennes seront désactivées, ce second chemin mourra
// avec elles : il faudra alors poser dans le Vault la MÊME valeur que celle du
// secret de la fonction, et c'est l'égalité exacte qui prendra le relais.
//
// SECRETS À POSER DANS SUPABASE (Edge Functions → Secrets) :
//   GEMINI_API_KEY               déjà posé au J20, partagé avec « ai-chat »
//   GEMINI_MODEL                 facultatif, pour changer de modèle sans code
//   SUPABASE_URL                 fournies d'office par la plateforme
//   SUPABASE_SERVICE_ROLE_KEY
//
// SECRETS À POSER DANS LE VAULT DE LA BASE (migration 032, section 6) :
//   ferha_functions_url          l'URL des fonctions du projet
//   ferha_service_role_key       la clé de service, en forme « eyJ… »
// =============================================================================

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/interactions";
const MODELE_PAR_DEFAUT = "gemini-3.5-flash-lite";

/// Vingt-cinq secondes par appel, et non soixante comme dans « ai-chat ».
///
/// LÀ-BAS QUELQU'UN ATTEND DEVANT SON ÉCRAN, et mieux vaut une réponse lente
/// qu'une panne. Ici personne n'attend, mais la fonction entière a un budget de
/// temps (voir `BUDGET_TEMPS_MS`) : un seul appel qui traîne coûterait la
/// synthèse de toutes les salles suivantes.
const DELAI_MODELE_MS = 25_000;

/// Un rejeu, pas deux — comme dans « ai-chat ». Si le modèle s'obstine, le
/// problème est le prompt, et un troisième appel ne fait que payer le quota.
const REJEUX_MAX = 1;

/// Combien de salles au plus par passage.
///
/// LE QUOTA GRATUIT EST LA RAISON, ET LA SEULE. Le hachage fait déjà que seules
/// les salles CHANGÉES sont traitées ; ce plafond ne sert que le jour où
/// beaucoup changent d'un coup — une réindexation, un changement de modèle.
/// Les salles non traitées repasseront la nuit suivante : elles sont toujours
/// « à refaire », rien ne les efface de la liste.
const SALLES_PAR_PASSAGE = 8;

/// LE BUDGET DE TEMPS DU PASSAGE ENTIER.
///
/// Une Edge Function est TUÉE au bout de son temps d'horloge — 150 secondes sur
/// le palier gratuit. Sans ce budget, un passage un peu long serait interrompu
/// au milieu d'un appel au modèle : le quota serait dépensé, la synthèse perdue,
/// et le journal ne dirait rien de ce qui a été fait.
///
/// On s'arrête donc AVANT, de nous-mêmes, entre deux salles — jamais au milieu
/// d'une. Les salles non traitées sont toujours « à refaire » : elles repassent
/// la nuit suivante, et rien ne les efface de la liste.
const BUDGET_TEMPS_MS = 100_000;

/// Les bornes de longueur de la synthèse.
///
/// Trois phrases, comme la maquette. Plus court ne dit rien ; plus long n'est
/// plus un résumé — et personne ne lit un paragraphe posé au-dessus des avis
/// qu'il résume.
const SYNTHESE_MIN = 80;
const SYNTHESE_MAX = 600;

const SCHEMA_SYNTHESE = {
  type: "object",
  properties: {
    synthese: { type: "string" },
    // Ce que le modèle déclare avoir mis en réserve. Le garde-fou 2 le lit ;
    // il ne s'affiche jamais.
    reserves: { type: "array", items: { type: "string" } },
  },
  required: ["synthese", "reserves"],
};

type Avis = { note: number; date: string; texte: string };

type SalleAResumer = {
  venue_id: string;
  name: string;
  review_count: number;
  notes_basses: number;
  source_hash: string;
  a_refaire: boolean;
  avis: Avis[];
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

/// Le 429 remonte avec son nom : il ne veut pas dire « panne » mais « demain ».
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
    headers: { "Content-Type": "application/json", "x-goog-api-key": cle },
    body: JSON.stringify({
      model: modele,
      system_instruction: instruction,
      input: entree,
      // On ne laisse aucune conversation côté Google.
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
  const texte: string = brut?.output_text ??
    brut?.steps?.[brut.steps.length - 1]?.content?.[0]?.text ?? "";

  if (!texte) throw new Error("le modèle a rendu une réponse vide");

  return JSON.parse(texte);
}

/// Les chiffres arabes-indiens ramenés à leurs équivalents européens.
///
/// Une synthèse en arabe peut écrire « ٣٥٠ » là où l'avis écrivait « 350 ». Sans
/// cette normalisation, le garde-fou verrait un nombre absent des avis et
/// rejetterait une synthèse correcte.
///
/// DEUX SÉRIES, ET NON UNE : U+0660..U+0669 sont les chiffres arabes-indiens,
/// U+06F0..U+06F9 leur variante persane. À l'œil, « ٠ » et « ۰ » ne se
/// distinguent pas — d'où des points de code plutôt qu'une classe de caractères
/// écrite en glyphes, où une plage fausse ne se verrait jamais.
function chiffresNormalises(texte: string): string {
  let sortie = "";
  for (const c of texte) {
    const code = c.codePointAt(0)!;
    if (code >= 0x0660 && code <= 0x0669) sortie += String(code - 0x0660);
    else if (code >= 0x06F0 && code <= 0x06F9) sortie += String(code - 0x06F0);
    else sortie += c;
  }
  return sortie;
}

/// GARDE-FOU 1 — les nombres de la synthèse viennent tous des avis.
///
/// On compare des SUITES DE CHIFFRES, séparateurs retirés : « 4,6 » et « 4.6 »
/// donnent « 46 », « 350 » donne « 350 ». Un nombre que personne n'a écrit est
/// un nombre calculé — une note moyenne, un comptage —, et le §8.2 dit
/// « aucune note recalculée ».
///
/// Rend la liste des nombres fautifs, vide quand tout va bien.
function chiffresInventes(synthese: string, avis: Avis[]): string[] {
  const source = chiffresNormalises(avis.map((a) => a.texte).join(" "));
  const nombresSource = new Set(source.match(/\d+/g) ?? []);

  const fautifs: string[] = [];
  for (const nombre of chiffresNormalises(synthese).match(/\d+/g) ?? []) {
    if (!nombresSource.has(nombre)) fautifs.push(nombre);
  }
  return fautifs;
}

/// Le jeton présenté est-il celui de la tâche nocturne ?
///
/// DEUX FORMES ACCEPTÉES, PARCE QUE SUPABASE EN A DEUX — voir l'en-tête :
///
///   1. Le jeton est EXACTEMENT la clé de service que la plateforme nous donne.
///      Vrai quel que soit le système de clés, et c'est le cas du cron : il lit
///      la même valeur dans le Vault. C'est le contrôle principal.
///
///   2. À défaut, c'est un JWT dont la revendication `role` vaut
///      `service_role` — la forme ancienne. ON NE VÉRIFIE PAS SA SIGNATURE, et
///      il ne faut pas : `verify_jwt` = true l'a fait avant nous, avec la clé
///      du projet que nous n'avons pas. Ce second chemin existe pour qu'une
///      rotation de clé ne fasse pas taire la synthèse en silence.
///
/// LA CLÉ PUBLIQUE NE PASSE NI L'UN NI L'AUTRE, et c'est tout l'enjeu. Vérifié
/// dans les deux sens : la clé publiable (pas un JWT) est refusée, et la clé
/// anonyme ancienne — un JWT authentique du projet, mais de rôle `anon` — l'est
/// aussi. Ce n'est pas « un JWT du projet » qui ouvre, c'est le rôle.
function estLaTacheNocturne(entete: string | null, cleService: string): boolean {
  const jeton = (entete ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!jeton) return false;
  if (jeton === cleService) return true;

  const parties = jeton.split(".");
  if (parties.length !== 3) return false;
  try {
    const charge = parties[1].replace(/-/g, "+").replace(/_/g, "/");
    const decode = atob(charge.padEnd(Math.ceil(charge.length / 4) * 4, "="));
    return JSON.parse(decode)?.role === "service_role";
  } catch {
    return false;
  }
}

// -----------------------------------------------------------------------------
// L'instruction
// -----------------------------------------------------------------------------

function instructionSynthese(): string {
  return `Tu résumes les avis laissés par des familles qui ont réellement organisé
une fête dans une salle, en Algérie. Tu écris pour quelqu'un qui hésite à réserver.

CE QUE TU AS : le texte des avis, et leur note sur 5. Rien d'autre.

RÈGLES, dans l'ordre d'importance :

1. N'ÉCRIS QUE CE QUE LES AVIS DISENT. Pas un équipement, pas un détail, pas une
   qualité qui ne soit dans l'un des textes que tu as sous les yeux. Si tu hésites,
   n'écris pas.

2. AUCUN CHIFFRE QUI NE SOIT DÉJÀ DANS UN AVIS. Ni note moyenne, ni pourcentage,
   ni « 3 clients sur 4 », ni nombre d'avis. Tu ne comptes rien et tu ne calcules
   rien. Écris « plusieurs », « la plupart », « un client » — jamais un nombre
   que tu aurais obtenu en comptant.

3. DIS LES RÉSERVES. Un résumé qui ne contient que des éloges n'est pas cru, et
   il ne sert à personne. Quand un avis émet une réserve — même en passant, même
   poliment —, elle doit se retrouver dans le résumé. Remplis aussi le champ
   « reserves » avec ces réserves, une par entrée, en quelques mots.
   Si vraiment aucun avis n'exprime la moindre réserve, laisse le champ vide.

4. NE NOMME PERSONNE. Tu n'as aucun nom de client, et tu n'en inventes pas.
   Ne nomme pas non plus la salle : le lecteur sait de quelle salle il s'agit.

5. TROIS PHRASES AU PLUS. Commence par ce qui revient le plus souvent, enchaîne
   sur les réserves. Pas d'introduction, pas de conclusion, pas de « en résumé ».

6. ÉCRIS DANS LA LANGUE DE LA MAJORITÉ DES AVIS. Si les avis sont en français,
   écris en français ; s'ils sont en arabe, écris en arabe. Ne traduis pas.

7. PARLE DES CLIENTS À LA TROISIÈME PERSONNE — « les invités saluent »,
   « plusieurs clients regrettent ». Tu rapportes, tu ne témoignes pas.`;
}

// -----------------------------------------------------------------------------
// Une salle
// -----------------------------------------------------------------------------

type Resultat = {
  venue_id: string;
  nom: string;
  statut: "ecrite" | "refusee" | "sans_reserve" | "chiffres" | "longueur";
  detail?: string;
};

async function resumerUneSalle(
  salle: SalleAResumer,
  cleGemini: string,
  modele: string,
  supabaseUrl: string,
  cleService: string,
): Promise<Resultat> {
  const entree = JSON.stringify({
    // Ni le nom de la salle, ni sa commune, ni sa note : voir l'en-tête.
    // Le modèle n'a que ce qu'il doit résumer.
    avis: salle.avis.map((a) => ({ note: a.note, texte: a.texte })),
  });

  let retenue = "";
  let derniereFaute: Resultat | null = null;

  for (let essai = 0; essai <= REJEUX_MAX; essai++) {
    const sortie = await demanderAuModele(
      cleGemini, modele, instructionSynthese(), entree, SCHEMA_SYNTHESE,
    );

    const texte = String(sortie.synthese ?? "").trim();
    const reserves = (Array.isArray(sortie.reserves) ? sortie.reserves : [])
      .map((r) => String(r).trim()).filter((r) => r.length > 0);

    if (texte.length < SYNTHESE_MIN || texte.length > SYNTHESE_MAX) {
      derniereFaute = {
        venue_id: salle.venue_id,
        nom: salle.name,
        statut: "longueur",
        detail: `${texte.length} caractères`,
      };
      console.error(`${salle.name} — longueur hors bornes (essai ${essai + 1}).`);
      continue;
    }

    // GARDE-FOU 1.
    const inventes = chiffresInventes(texte, salle.avis);
    if (inventes.length > 0) {
      derniereFaute = {
        venue_id: salle.venue_id,
        nom: salle.name,
        statut: "chiffres",
        detail: inventes.join(", "),
      };
      console.error(
        `${salle.name} — chiffres absents des avis (essai ${essai + 1}) : ` +
          inventes.join(", "),
      );
      continue;
    }

    // GARDE-FOU 2. La base a compté les avis tièdes ; s'il y en a, la synthèse
    // doit porter une réserve.
    if (salle.notes_basses > 0 && reserves.length === 0) {
      derniereFaute = {
        venue_id: salle.venue_id,
        nom: salle.name,
        statut: "sans_reserve",
        detail: `${salle.notes_basses} avis à 3 étoiles ou moins`,
      };
      console.error(
        `${salle.name} — aucune réserve déclarée alors que la base en compte ` +
          `${salle.notes_basses} (essai ${essai + 1}).`,
      );
      continue;
    }

    retenue = texte;
    break;
  }

  // AU SECOND ÉCHEC, ON N'ÉCRIT RIEN. Contrairement à l'agent, il n'y a pas de
  // repli acceptable : une liste brute de salles reste utile, une synthèse
  // fausse ne l'est pas. L'ancienne reste en place, et la salle repassera
  // demain — son hachage est toujours différent.
  if (!retenue) {
    return derniereFaute ?? {
      venue_id: salle.venue_id,
      nom: salle.name,
      statut: "refusee",
      detail: "aucune synthèse retenue",
    };
  }

  const ecrites = await rpc(
    supabaseUrl, cleService, "enregistrer_synthese_avis",
    {
      p_venue_id: salle.venue_id,
      p_summary: retenue,
      p_source_hash: salle.source_hash,
      p_review_count: salle.review_count,
      p_model: modele,
    },
  ) as number;

  if (ecrites === 0) {
    // La salle a été dépubliée, ou un avis a été retiré, entre la lecture et
    // l'écriture. Le SQL a refusé — c'est son travail.
    return {
      venue_id: salle.venue_id,
      nom: salle.name,
      statut: "refusee",
      detail: "la base a refusé : salle dépubliée, ou moins d’avis qu’il n’en faut",
    };
  }

  return { venue_id: salle.venue_id, nom: salle.name, statut: "ecrite" };
}

// -----------------------------------------------------------------------------
// Le passage
// -----------------------------------------------------------------------------

Deno.serve(async (requete: Request): Promise<Response> => {
  if (requete.method !== "POST") {
    return reponseHttp({ message: "Cette fonction ne répond qu'en POST." }, 405);
  }

  const cleGemini = Deno.env.get("GEMINI_API_KEY");
  const modele = Deno.env.get("GEMINI_MODEL") || MODELE_PAR_DEFAUT;
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const cleService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!cleGemini || !supabaseUrl || !cleService) {
    console.error("Configuration incomplète — GEMINI_API_KEY:" + Boolean(cleGemini));
    return reponseHttp({ message: "Synthèse non configurée." }, 500);
  }

  // SEUL LE CRON ENTRE, et le contrôle vient APRÈS la lecture des secrets parce
  // qu'il a besoin de la clé de service pour comparer. Voir l'en-tête : la clé
  // publique du projet ouvre la passerelle, elle ne doit pas ouvrir celle-ci.
  if (!estLaTacheNocturne(requete.headers.get("Authorization"), cleService)) {
    return reponseHttp({ message: "Réservé à la tâche nocturne." }, 403);
  }

  const debut = Date.now();

  try {
    const toutes = (await rpc(
      supabaseUrl, cleService, "avis_pour_synthese", { p_model: modele },
    )) as SalleAResumer[];

    const aRefaire = toutes.filter((s) => s.a_refaire).slice(0, SALLES_PAR_PASSAGE);

    const resultats: Resultat[] = [];
    let quota = false;
    let tempsEpuise = false;

    for (const salle of aRefaire) {
      // On ne COMMENCE pas une salle qu'on ne pourrait pas finir.
      if (Date.now() - debut > BUDGET_TEMPS_MS) {
        console.log("Budget de temps atteint — le passage s'arrête ici.");
        tempsEpuise = true;
        break;
      }

      try {
        resultats.push(
          await resumerUneSalle(salle, cleGemini, modele, supabaseUrl, cleService),
        );
      } catch (erreur) {
        if (erreur instanceof QuotaEpuise) {
          // ON S'ARRÊTE, ON NE CONTINUE PAS EN BOUCLE. Le quota est épuisé pour
          // la journée ; les salles restantes repasseront demain. Insister ne
          // ferait qu'ajouter des 429 au journal.
          console.error("Quota épuisé — le passage s'arrête ici.");
          quota = true;
          break;
        }
        console.error(`${salle.name} :`, erreur);
        resultats.push({
          venue_id: salle.venue_id,
          nom: salle.name,
          statut: "refusee",
          detail: String(erreur),
        });
      }
    }

    // LE JOURNAL DIT CE QU'ON A REGARDÉ, pas seulement ce qu'on a écrit. Savoir
    // qu'on a passé quinze salles en revue et rédigé une seule synthèse est
    // exactement ce qu'on veut lire au matin : c'est la preuve que le hachage
    // fait son travail, et que le quota n'est pas dépensé pour rien.
    const bilan = {
      salles_eligibles: toutes.length,
      a_refaire: toutes.filter((s) => s.a_refaire).length,
      traitees: resultats.length,
      ecrites: resultats.filter((r) => r.statut === "ecrite").length,
      quota_epuise: quota,
      temps_epuise: tempsEpuise,
      modele,
      duree_ms: Date.now() - debut,
      detail: resultats,
    };

    console.log("Synthèse des avis :", JSON.stringify(bilan));
    return reponseHttp(bilan);
  } catch (erreur) {
    console.error("summarize-reviews :", erreur);
    return reponseHttp({ message: "La synthèse n'a pas pu s'exécuter." }, 500);
  }
});
