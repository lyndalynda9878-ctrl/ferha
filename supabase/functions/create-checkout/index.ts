// =============================================================================
// Ferha — Edge Function « create-checkout » (§7.2, CLI-06)
//
// CE QU'ELLE FAIT : ouvre la page de paiement Chargily de l'acompte, et range
// la trace de cette page dans payments. Rien d'autre. Elle ne confirme aucune
// réservation — c'est le webhook du J16 qui le fera, et lui seul.
//
// POURQUOI ELLE EXISTE PLUTÔT QU'UN APPEL DEPUIS FLUTTER. La clé secrète
// Chargily ne doit jamais entrer dans l'application (§9.4 du cahier des
// charges : « un APK se décompile en quelques minutes »). Elle vit dans les
// secrets de cette fonction, sous le nom CHARGILY_SECRET_KEY, et n'en sort pas.
// Flutter appelle cette fonction avec le JETON DE L'UTILISATEUR, et n'apprend
// jamais qu'une clé existe.
//
// MODE TEST, ET RIEN D'AUTRE (v2.0, CLI-06). L'URL de base est celle du mode
// test ; is_test vaut true sur chaque ligne payments écrite. Le passage en réel
// changera cette constante et la clé du secret, pas le reste du fichier.
//
// LE MONTANT NE VIENT PAS DE FLUTTER. Le corps de la requête ne porte pas de
// montant, et cette fonction n'en accepterait pas : elle demande à
// acompte_a_verser() (024) ce qui est dû, et enregistrer_checkout() le relit une
// seconde fois dans la base au moment d'écrire. Deux lectures, zéro confiance.
//
// LES TROIS REFUS SONT CEUX DE LA BASE, PAS LES SIENS. Sans session, pour la
// réservation d'un autre, ou quand tient_la_date() ne dit pas « option » :
// acompte_a_verser() lève, et cette fonction se contente de recopier le code
// Ferha et le statut HTTP. Un garde-fou écrit ici serait un second exemplaire
// d'une règle qui n'en a qu'un.
//
// UNE SEULE PAGE DE PAIEMENT ACTIVE PAR RÉSERVATION. Un second « Payer » —
// double tap, retour arrière, page rechargée — ne crée pas un second checkout :
// on retrouve celui qui est déjà ouvert chez Chargily et on rend SON url. On ne
// le réutilise que s'il est encore « pending » ET que son montant est toujours
// celui de la base ; un checkout périmé, payé, ou devenu faux laisse la place à
// un neuf.
//
// REVENIR SUR success_url NE CONFIRME RIEN, et le §9 le demande explicitement
// (« l'endpoint est idempotent », webhook signé). L'écran de retour dit
// « paiement en cours de vérification » et la réservation reste « accepted »
// jusqu'à ce que chargily-webhook parle — c'est lui, et lui seul, qui confirme.
//
// L'ADRESSE DE CE WEBHOOK PART AVEC CHAQUE CHECKOUT (webhook_endpoint), pour
// n'avoir rien à régler à la main dans le tableau de bord Chargily.
//
// SECRETS ET VARIABLES
//   CHARGILY_SECRET_KEY   obligatoire, posée à la main dans le tableau de bord
//                         Supabase (Edge Functions › Secrets). Jamais dans le
//                         dépôt, jamais dans Flutter.
//   SUPABASE_URL          fournies d'office par la plateforme.
//   SUPABASE_ANON_KEY
//   SUPABASE_SERVICE_ROLE_KEY
//   APP_ORIGIN            facultative. Quand elle est posée, seules les URL de
//                         retour de CETTE origine (et celles de la machine de
//                         développement) sont acceptées. Voir urlDeRetour().
// =============================================================================

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

/// Mode test de Chargily Pay v2, et lui seul (CLI-06).
///
/// Le mode réel serait « https://pay.chargily.net/api/v2 », avec la clé de
/// l'autre environnement. Les deux ne se mélangent pas : une clé de test sur
/// l'URL réelle ne s'authentifie pas.
const CHARGILY_API = "https://pay.chargily.net/test/api/v2";

/// La langue de la page de paiement. Chargily accepte 'ar', 'en' ou 'fr'.
const LOCALE_CHARGILY = "fr";

const ENTETES_CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/// Une réponse JSON, toujours avec les en-têtes CORS : l'appelant est une page
/// web servie depuis une autre origine que celle de la fonction.
function reponse(corps: unknown, statut = 200): Response {
  return new Response(JSON.stringify(corps), {
    status: statut,
    headers: { ...ENTETES_CORS, "Content-Type": "application/json" },
  });
}

/// Un refus, dans la forme que Flutter sait lire.
///
/// `hint` porte le code Ferha, comme le fait PostgREST pour les exceptions SQL :
/// c'est le code que lit acompte_messages.dart, jamais le message. Le message
/// reste là pour les journaux et pour le cas non traduit.
function refus(hint: string, message: string, statut: number): Response {
  return reponse({ hint, message }, statut);
}

/// Valide une URL de retour envoyée par l'application.
///
/// POURQUOI L'APPLICATION LES ENVOIE PLUTÔT QUE LA FONCTION LES CONSTRUIRE.
/// L'application web tourne sur un port que `flutter run` choisit à chaque
/// démarrage — http://localhost:52731 aujourd'hui, un autre demain. Une adresse
/// figée dans un secret serait fausse une fois sur deux, et il n'y a rien à
/// gagner à la figer : revenir sur success_url ne confirme AUCUN paiement, c'est
/// le webhook du J16 qui confirme. Le pire qu'un appelant malveillant obtienne
/// en mentant ici, c'est d'être renvoyé ailleurs après avoir payé SA PROPRE
/// réservation.
///
/// On vérifie donc deux choses, et elles suffisent :
///   * le schéma est http ou https — c'est la règle de Chargily elle-même
///     (« must be a valid URL that begins with either http or https ») ;
///   * si APP_ORIGIN est posée, l'origine est la sienne, ou une origine locale.
///     Le jour où l'application aura un domaine, cette variable ferme la porte
///     sans qu'une ligne de code change.
function urlDeRetour(brut: unknown): string | null {
  if (typeof brut !== "string" || brut.length === 0 || brut.length > 2000) {
    return null;
  }

  let url: URL;
  try {
    url = new URL(brut);
  } catch {
    return null;
  }

  if (url.protocol !== "http:" && url.protocol !== "https:") return null;

  const attendue = Deno.env.get("APP_ORIGIN");
  if (attendue && attendue.length > 0) {
    const locale = url.hostname === "localhost" || url.hostname === "127.0.0.1";
    if (url.origin !== attendue && !locale) return null;
  }

  return url.toString();
}

/// L'acompte tel que la base le dit — une ligne d'acompte_a_verser().
interface AcompteDu {
  group_id: string;
  booking_id: string;
  venue_id: string;
  venue_name: string;
  event_date: string;
  acompte: number;
  checkout_id: string | null;
}

/// Le corps d'erreur que rend PostgREST : on en garde le code Ferha.
interface ErreurPostgrest {
  hint?: string | null;
  message?: string | null;
}

Deno.serve(async (requete: Request): Promise<Response> => {
  // Le pré-vol du navigateur. Sans lui, l'appel depuis Flutter web n'a même pas
  // lieu.
  if (requete.method === "OPTIONS") {
    return new Response("ok", { headers: ENTETES_CORS });
  }

  if (requete.method !== "POST") {
    return refus("FE056", "Cette fonction ne répond qu'en POST.", 405);
  }

  const cleChargily = Deno.env.get("CHARGILY_SECRET_KEY");
  if (!cleChargily) {
    // Le message rendu au client ne nomme aucun secret : il n'a pas à savoir
    // comment le serveur est configuré. Le journal, lui, le dit en toutes
    // lettres à qui déploie.
    console.error(
      "CHARGILY_SECRET_KEY absente des secrets de la Edge Function.",
    );
    return refus(
      "FE058",
      "Le paiement en ligne n'est pas configuré sur ce serveur.",
      503,
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const cleAnon = Deno.env.get("SUPABASE_ANON_KEY");
  const cleService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !cleAnon || !cleService) {
    console.error("Variables Supabase absentes de l'environnement.");
    return refus("FE058", "Le paiement n'est pas disponible pour le moment.", 503);
  }

  // Le jeton de l'utilisateur, recopié tel quel vers PostgREST : c'est lui qui
  // fait que auth.uid() existe, et donc que la base peut vérifier à qui est la
  // réservation.
  const autorisation = requete.headers.get("Authorization");
  if (!autorisation) {
    return refus("FE050", "Il faut être connecté pour verser un acompte.", 401);
  }

  let corps: Record<string, unknown>;
  try {
    corps = await requete.json();
  } catch {
    return refus("FE057", "Requête illisible.", 400);
  }

  const bookingId = corps["booking_id"];
  if (typeof bookingId !== "string" || bookingId.length === 0) {
    return refus("FE057", "Réservation non précisée.", 400);
  }

  const methode = corps["methode"];
  if (methode !== "cib" && methode !== "edahabia") {
    return refus("FE055", "Choisissez CIB ou Edahabia.", 400);
  }

  const retourSucces = urlDeRetour(corps["retour_succes"]);
  const retourEchec = urlDeRetour(corps["retour_echec"]);
  if (!retourSucces || !retourEchec) {
    return refus("FE057", "Adresse de retour invalide.", 400);
  }

  // ---------------------------------------------------------------------------
  // 1. Ce qui est dû, d'après la base — et les refus, qui viennent d'elle
  // ---------------------------------------------------------------------------

  const lecture = await fetch(`${supabaseUrl}/rest/v1/rpc/acompte_a_verser`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: cleAnon,
      Authorization: autorisation,
    },
    body: JSON.stringify({ p_booking_id: bookingId }),
  });

  if (!lecture.ok) {
    const erreur = (await lecture.json().catch(() => ({}))) as ErreurPostgrest;
    // Le code Ferha et le statut passent tels quels : la phrase française est
    // écrite dans l'application, pas ici.
    return refus(
      erreur.hint ?? "FE059",
      erreur.message ?? "L'acompte n'a pas pu être préparé.",
      lecture.status,
    );
  }

  const lignes = (await lecture.json()) as AcompteDu[];
  const du = lignes[0];
  if (!du) {
    return refus("FE051", "Cette réservation n'est pas la vôtre.", 403);
  }

  // ---------------------------------------------------------------------------
  // 2. La page déjà ouverte, si elle l'est encore
  //
  // On interroge Chargily plutôt que de garder une URL en base : c'est lui qui
  // sait si sa page vaut encore, et une URL rangée chez nous vieillirait en
  // silence. Un échec de cette lecture n'est pas fatal — on repart sur un
  // checkout neuf, ce qui est au pire une page abandonnée de plus.
  // ---------------------------------------------------------------------------

  if (du.checkout_id) {
    try {
      const relecture = await fetch(
        `${CHARGILY_API}/checkouts/${encodeURIComponent(du.checkout_id)}`,
        { headers: { Authorization: `Bearer ${cleChargily}` } },
      );

      if (relecture.ok) {
        const checkout = await relecture.json();

        // Déjà payé : on n'ouvre pas une seconde page pour encaisser deux fois.
        // La réservation reste « accepted » — c'est le webhook du J16 qui la
        // confirmera, et l'écran dit « en cours de vérification » en attendant.
        if (checkout.status === "paid") {
          return reponse({
            url: null,
            montant: du.acompte,
            deja_paye: true,
            reutilise: false,
          });
        }

        // Encore ouverte, et toujours du bon montant : c'est la même page.
        const encoreOuverte = checkout.status === "pending" ||
          checkout.status === "processing";
        if (encoreOuverte && checkout.amount === du.acompte) {
          return reponse({
            url: checkout.checkout_url,
            montant: du.acompte,
            deja_paye: false,
            reutilise: true,
          });
        }
      }
    } catch (erreur) {
      console.error("Relecture du checkout impossible :", erreur);
    }
  }

  // ---------------------------------------------------------------------------
  // 3. Une page neuve
  // ---------------------------------------------------------------------------

  const creation = await fetch(`${CHARGILY_API}/checkouts`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${cleChargily}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      // Des dinars ENTIERS, arrondis une seule fois — par montant_acompte()
      // (024), en SQL.
      amount: du.acompte,
      currency: "dzd",
      payment_method: methode,
      success_url: retourSucces,
      failure_url: retourEchec,
      locale: LOCALE_CHARGILY,
      // OÙ NOUS PRÉVENIR — et le nom du champ se joue ici.
      //
      // Le guide « Webhooks » dit « webhook_url » ; la RÉFÉRENCE API dit
      // « webhook_endpoint », et l'objet Checkout qu'elle rend porte un
      // attribut de ce nom. C'est la référence qui fait foi : un objet ne
      // renvoie pas un champ sous un nom qu'il n'accepte pas. Le guide est
      // resté en arrière.
      //
      // Le déclarer ICI plutôt que dans le tableau de bord Chargily est
      // délibéré : l'adresse suit le projet. Un projet Supabase recréé, une
      // clé regénérée, et le reglage fait à la main un jour dans une interface
      // serait faux sans que personne ne s'en aperçoive — les paiements
      // partiraient, et aucune reservation ne se confirmerait.
      webhook_endpoint: `${supabaseUrl}/functions/v1/chargily-webhook`,
      description: `Acompte Ferha — ${du.venue_name}, le ${du.event_date}`,
      // Le rapprochement comptable du §4.4 (ADM-03) : le webhook du J16
      // retrouvera la réservation par checkout_id, et ces deux clés font la
      // même chose depuis le tableau de bord Chargily.
      metadata: {
        booking_id: du.booking_id,
        group_id: du.group_id,
      },
    }),
  });

  if (!creation.ok) {
    // Le corps de Chargily est ce qui dit POURQUOI — un champ refusé, une clé
    // du mauvais mode. Il va au journal en entier ; le client, lui, reçoit une
    // phrase.
    const detail = await creation.text().catch(() => "");
    console.error(
      `Chargily a refusé la création du checkout (${creation.status}) : ${detail}`,
    );
    return refus(
      "FE059",
      "La page de paiement n'a pas pu être ouverte. Réessayez dans un instant.",
      502,
    );
  }

  const checkout = await creation.json();
  if (!checkout?.id || !checkout?.checkout_url) {
    console.error("Réponse Chargily inattendue :", JSON.stringify(checkout));
    return refus("FE059", "La page de paiement n'a pas pu être ouverte.", 502);
  }

  // ---------------------------------------------------------------------------
  // 4. La trace, en service_role — la seule écriture possible sur payments
  //
  // APRÈS la création, et pas avant : une ligne « pending » sans checkout_id ne
  // dit rien à personne, alors qu'un checkout sans ligne se rattrape — le
  // webhook du J16 porte l'identifiant, et le tableau de bord Chargily aussi.
  // ---------------------------------------------------------------------------

  const trace = await fetch(`${supabaseUrl}/rest/v1/rpc/enregistrer_checkout`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: cleService,
      Authorization: `Bearer ${cleService}`,
    },
    body: JSON.stringify({
      p_booking_id: du.booking_id,
      p_checkout_id: checkout.id,
      p_method: methode,
    }),
  });

  if (!trace.ok) {
    const detail = await trace.text().catch(() => "");
    console.error(
      `payments non écrite pour le checkout ${checkout.id} : ${detail}`,
    );
    return refus(
      "FE059",
      "Le paiement n'a pas pu être enregistré. Réessayez dans un instant.",
      502,
    );
  }

  return reponse({
    url: checkout.checkout_url,
    montant: du.acompte,
    deja_paye: false,
    reutilise: false,
  });
});
