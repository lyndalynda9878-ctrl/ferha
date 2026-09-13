// =============================================================================
// Ferha — Edge Function « embed-venue » (§7.2, §8.3, §8.4)
//
// CE QU'ELLE FAIT : elle va chercher les salles publiées dont l'empreinte est à
// refaire, les fait vectoriser par le service d'empreintes, et range les
// vecteurs. Elle ne décide de RIEN — ni de ce qui est publié, ni de ce qui a
// changé, ni du texte à vectoriser. Tout cela vit dans la migration 027 :
// `salles_a_indexer()` répond aux deux premières questions,
// `document_salle()` à la troisième.
//
// C'EST VOULU, ET C'EST LA MÊME RÈGLE QUE POUR chargily-webhook. Ce fichier est
// un transporteur : il prend du texte à un bout, rapporte des nombres à
// l'autre. Le jour où quelqu'un écrira un second indexeur — un déclencheur SQL,
// une tâche planifiée —, il n'aura aucune règle à recopier, donc aucune règle à
// recopier de travers. Un filtre « status = published » écrit ici serait un
// second gardien pour une règle qui vit déjà dans la base, et c'est le second
// gardien qu'on oublie de mettre à jour.
//
// =============================================================================
// verify_jwt = FALSE, ET LA PORTE EST INDEX_TOKEN
//
// La clé « anon » de Supabase est PUBLIQUE — elle est compilée dans
// l'application Flutter. Exiger un JWT ne filtrerait donc que les robots qui
// passent sans rien, et laisserait entrer quiconque a ouvert l'application une
// fois. Ce qui protège cette fonction est un secret partagé qui n'est nulle
// part ailleurs, comparé en temps constant — exactement comme la signature de
// chargily-webhook (J16), et pour la même raison.
//
// =============================================================================
// ON RÉVEILLE LE SERVICE AVANT DE LUI PARLER
//
// L'offre gratuite de Render endort le service après quinze minutes, et
// l'indexation est précisément le genre de chose qu'on lance une fois par
// semaine. Le premier appel après une sieste attend le réveil — trente à
// soixante secondes. On frappe donc à /health d'abord, qui ne demande pas de
// jeton, et on ne compte le temps qu'après.
//
// =============================================================================
// LE NOM DU MODÈLE VIENT DU SERVICE, ON NE L'ÉCRIT PAS ICI
//
// C'est /health qui dit quel modèle tourne. Si le service change de modèle un
// jour, cette fonction le verra, le passera à `salles_a_indexer()`, et TOUT
// sera marqué à refaire — sans qu'une ligne de ce fichier ait bougé. Écrire le
// nom en dur ici créerait la panne la plus sournoise du projet : des vecteurs
// d'un modèle comparés à ceux d'un autre, sans erreur, avec des résultats
// simplement faux.
//
// On revérifie ce nom sur CHAQUE réponse d'empreintes : un service redéployé au
// milieu d'un passage donnerait sinon un lot d'un modèle et un lot de l'autre.
//
// =============================================================================
// PAR PAQUETS DE QUINZE
//
// Le service tourne sur 0,1 vCPU. Un lot de soixante textes longs y prend
// plusieurs dizaines de secondes, et une Edge Function n'a pas ce temps. Quinze
// est le plafond mesuré au J18 comme raisonnable ; c'est aussi, pour l'instant,
// le catalogue entier en un seul appel.
//
// SECRETS À POSER DANS SUPABASE (Edge Functions → Secrets) :
//   INDEX_TOKEN                  la porte de cette fonction
//   EMBEDDINGS_URL               https://ferha-embeddings.onrender.com
//   EMBED_TOKEN                  le jeton du service d'empreintes
//   SUPABASE_URL                 fournies d'office par la plateforme
//   SUPABASE_SERVICE_ROLE_KEY
// =============================================================================

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

/// Combien de textes par appel au service. Voir l'en-tête.
const TAILLE_LOT = 15;

/// Le réveil peut être long ; le calcul aussi, sur un dixième de vCPU.
const DELAI_REVEIL_MS = 90_000;
const DELAI_EMPREINTES_MS = 120_000;

type Salle = {
  venue_id: string;
  name: string;
  content: string;
  content_hash: string;
  a_refaire: boolean;
};

/// Compare deux chaînes en temps constant.
///
/// Une comparaison ordinaire s'arrête au premier caractère qui diffère, et le
/// temps qu'elle met à répondre dit combien étaient justes.
function memeJeton(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let i = 0; i < a.length; i++) {
    difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return difference === 0;
}

function reponse(corps: unknown, statut = 200): Response {
  return new Response(JSON.stringify(corps), {
    status: statut,
    headers: { "Content-Type": "application/json" },
  });
}

/// Un appel RPC à PostgREST, en droits de service.
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
    const detail = await appel.text().catch(() => "");
    throw new Error(`${fonction} a échoué (${appel.status}) : ${detail}`);
  }

  return await appel.json();
}

Deno.serve(async (requete: Request): Promise<Response> => {
  if (requete.method !== "POST") {
    return reponse({ message: "Cette fonction ne répond qu'en POST." }, 405);
  }

  const jetonAttendu = Deno.env.get("INDEX_TOKEN");
  const serviceUrl = Deno.env.get("EMBEDDINGS_URL");
  const jetonService = Deno.env.get("EMBED_TOKEN");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const cleService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!jetonAttendu || !serviceUrl || !jetonService || !supabaseUrl || !cleService) {
    // On ne dit pas LEQUEL manque : la réponse est publique. Le journal, lui,
    // est lisible depuis le tableau de bord et peut être précis.
    console.error(
      "Configuration incomplète — INDEX_TOKEN:" + Boolean(jetonAttendu) +
        " EMBEDDINGS_URL:" + Boolean(serviceUrl) +
        " EMBED_TOKEN:" + Boolean(jetonService),
    );
    return reponse({ message: "Fonction non configurée." }, 500);
  }

  const jetonDonne = requete.headers.get("x-index-token") ?? "";
  if (!memeJeton(jetonDonne, jetonAttendu)) {
    console.error("Appel à embed-venue sans jeton valide : ignoré.");
    return reponse({ message: "Jeton absent ou invalide." }, 401);
  }

  // `force` refait tout, hachage identique ou non. Il ne sert pas au train-train
  // — le hachage s'en charge — mais au jour où l'on soupçonne un vecteur écrit
  // de travers, ou après un changement de modèle qu'on veut appliquer tout de
  // suite. Un corps vide vaut « pas de force ».
  let force = false;
  try {
    const corps = await requete.json();
    force = corps?.force === true;
  } catch {
    // Pas de corps, ou corps illisible : ce n'est pas une erreur.
  }

  const debut = Date.now();

  // ---------------------------------------------------------------------------
  // 1. Réveiller le service, et lui demander quel modèle il fait tourner.
  // ---------------------------------------------------------------------------

  let modele: string;
  let dimensions: number;
  try {
    const sante = await fetch(`${serviceUrl}/health`, {
      signal: AbortSignal.timeout(DELAI_REVEIL_MS),
    });
    if (!sante.ok) throw new Error(`/health a rendu ${sante.status}`);

    const etat = await sante.json();
    modele = String(etat?.modele ?? "");
    dimensions = Number(etat?.dimensions ?? 0);

    if (!modele || dimensions !== 384) {
      throw new Error(`modèle « ${modele} », ${dimensions} dimensions`);
    }
  } catch (erreur) {
    console.error("Le service d'empreintes n'a pas répondu :", erreur);
    return reponse(
      { message: "Le service d'empreintes est injoignable.", detail: String(erreur) },
      503,
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Demander à la base ce qu'il y a à faire.
  // ---------------------------------------------------------------------------

  let salles: Salle[];
  try {
    salles = (await rpc(supabaseUrl, cleService, "salles_a_indexer", {
      p_model: modele,
    })) as Salle[];
  } catch (erreur) {
    console.error("salles_a_indexer a échoué :", erreur);
    return reponse({ message: "La base n'a pas répondu." }, 500);
  }

  const aFaire = force ? salles : salles.filter((s) => s.a_refaire);
  const inchangees = salles.length - aFaire.length;

  if (aFaire.length === 0) {
    console.log(`Rien à faire : ${inchangees} salle(s) déjà à jour.`);
    return reponse({
      modele,
      publiees: salles.length,
      indexees: 0,
      inchangees,
      echecs: 0,
      details: [],
      duree_ms: Date.now() - debut,
    });
  }

  // ---------------------------------------------------------------------------
  // 3. Vectoriser, par paquets, et ranger au fur et à mesure.
  //
  // ON ÉCRIT APRÈS CHAQUE PAQUET, et non à la fin. Si le troisième paquet
  // échoue, les deux premiers sont déjà en base : le passage suivant n'aura
  // qu'un tiers du travail à refaire, et le hachage le saura tout seul.
  // ---------------------------------------------------------------------------

  let indexees = 0;
  let echecs = 0;
  const details: string[] = [];

  for (let debutLot = 0; debutLot < aFaire.length; debutLot += TAILLE_LOT) {
    const lot = aFaire.slice(debutLot, debutLot + TAILLE_LOT);

    let vecteurs: number[][];
    try {
      const appel = await fetch(`${serviceUrl}/embed`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${jetonService}`,
        },
        // `nature: "salle"` pose le préfixe « passage: » côté service. On ne
        // l'écrit pas ici : les deux préfixes d'E5 sont une affaire du modèle,
        // et le service est le seul endroit du projet qui les connaisse.
        body: JSON.stringify({
          textes: lot.map((s) => s.content),
          nature: "salle",
        }),
        signal: AbortSignal.timeout(DELAI_EMPREINTES_MS),
      });

      if (!appel.ok) {
        throw new Error(
          `/embed a rendu ${appel.status} : ${await appel.text().catch(() => "")}`,
        );
      }

      const resultat = await appel.json();

      // LE MODÈLE A-T-IL CHANGÉ SOUS NOS PIEDS ? Un redéploiement du service au
      // milieu d'un passage mélangerait deux systèmes de coordonnées dans la
      // même table. On arrête plutôt que d'écrire ça.
      if (String(resultat?.modele) !== modele) {
        throw new Error(
          `le service a changé de modèle en cours de route : « ${resultat?.modele} » ` +
            `au lieu de « ${modele} »`,
        );
      }

      vecteurs = resultat?.vecteurs as number[][];
      if (!Array.isArray(vecteurs) || vecteurs.length !== lot.length) {
        throw new Error(
          `${vecteurs?.length ?? 0} vecteur(s) pour ${lot.length} salle(s)`,
        );
      }
    } catch (erreur) {
      echecs += lot.length;
      details.push(`lot de ${lot.length} : ${String(erreur)}`);
      console.error("Lot en échec :", erreur);
      continue;
    }

    for (let i = 0; i < lot.length; i++) {
      const salle = lot[i];
      try {
        const ecrites = await rpc(
          supabaseUrl,
          cleService,
          "enregistrer_empreinte",
          {
            p_venue_id: salle.venue_id,
            p_content: salle.content,
            p_content_hash: salle.content_hash,
            // pgvector accepte le littéral « [0.1,0.2,…] ». On l'écrit
            // explicitement : un tableau JSON brut serait reçu comme un
            // `json`, et la conversion en `vector` n'est pas implicite.
            p_embedding: `[${vecteurs[i].join(",")}]`,
            p_model: modele,
          },
        );

        if (ecrites === 0) {
          // La salle a été dépubliée pendant qu'on calculait. Ce n'est pas un
          // échec : c'est la base qui a eu raison de revérifier.
          details.push(`${salle.name} : dépubliée entre-temps, non indexée`);
        } else {
          indexees++;
        }
      } catch (erreur) {
        echecs++;
        details.push(`${salle.name} : ${String(erreur)}`);
        console.error(`Écriture impossible pour ${salle.name} :`, erreur);
      }
    }
  }

  const resume = {
    modele,
    publiees: salles.length,
    indexees,
    inchangees,
    echecs,
    details,
    duree_ms: Date.now() - debut,
  };

  console.log(
    `embed-venue : ${indexees} indexée(s), ${inchangees} inchangée(s), ` +
      `${echecs} échec(s) en ${resume.duree_ms} ms.`,
  );

  // 200 même avec des échecs partiels : le résumé les porte, et l'appelant a
  // besoin de savoir ce qui EST passé. Un 500 laisserait croire que rien n'a
  // été écrit.
  return reponse(resume, echecs > 0 && indexees === 0 ? 502 : 200);
});
