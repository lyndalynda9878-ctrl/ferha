// =============================================================================
// Ferha — Edge Function « chargily-webhook » (§7.2, CLI-06)
//
// CE QU'ELLE FAIT : elle vérifie que l'appel vient bien de Chargily, puis passe
// la main à la base. Elle ne décide de RIEN — ni du montant, ni de l'option, ni
// de l'idempotence. Tout cela se joue dans confirmer_paiement_chargily() (025),
// en une seule transaction, sur une ligne verrouillée.
//
// C'EST LA DIFFÉRENCE ENTRE CE FICHIER ET UN VRAI PORTIER. Ce qu'il garde, ce
// n'est pas la logique métier : c'est l'authenticité. Deux livraisons
// simultanées du même événement, un montant trafiqué, une date expirée — la
// base sait répondre à tout cela mieux que du TypeScript, parce qu'elle peut
// verrouiller et revenir en arrière.
//
// verify_jwt = FALSE, ET C'EST OBLIGATOIRE. Chargily n'a aucun jeton Supabase
// et n'en aura jamais : cette fonction est ouverte sur Internet. Ce qui la
// protège, c'est LA SIGNATURE, et elle seule. Il n'y a pas de second garde-fou,
// et il ne faut pas en chercher un ailleurs — un filtre d'adresse IP se
// contourne et se périme, une clé dans l'URL se retrouve dans les journaux.
//
// LA SIGNATURE SE VÉRIFIE SUR LE CORPS BRUT, AVANT TOUT DÉCODAGE. C'est le
// point le plus facile à rater : `JSON.parse` puis `JSON.stringify` rendraient
// un texte différent de celui qui a été signé — un espace, un ordre de clés, un
// nombre réécrit — et la vérification échouerait, ou pire, porterait sur autre
// chose que ce qu'on va lire. On lit donc `req.text()` UNE fois, on le vérifie,
// et on ne décode qu'après.
//
// L'ALGORITHME EST CELUI DE LA DOCUMENTATION, pas un choix : en-tête
// `signature`, HMAC-SHA256 du corps avec la clé secrète d'API, en hexadécimal
// minuscule. Aucun horodatage, aucun préfixe, aucune version dans l'en-tête —
// ce n'est pas le format de Stripe, et le copier ici ne marcherait pas.
//
// ON RÉPOND 200 À TOUT CE QUI EST AUTHENTIQUE, même quand l'histoire finit mal.
// Un webhook non acquitté est un webhook que Chargily renvoie ; redemander
// indéfiniment un événement dont le problème est « cette date est déjà vendue »
// ne réglerait rien et noierait les journaux. Les 401 sont donc réservés aux
// signatures fausses, et les 500 aux pannes qui valent un nouvel essai.
//
// SECRETS
//   CHARGILY_SECRET_KEY          la même clé qu'à la création du checkout :
//                                c'est elle qui signe. Posée à la main dans le
//                                tableau de bord Supabase.
//   SUPABASE_URL                 fournies d'office par la plateforme.
//   SUPABASE_SERVICE_ROLE_KEY
// =============================================================================

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const ENCODEUR = new TextEncoder();

/// Le HMAC-SHA256 du corps, en hexadécimal minuscule.
///
/// Web Crypto plutôt que node:crypto : c'est l'API native du runtime Deno de
/// Supabase, et elle n'a rien à importer.
async function signatureDe(cle: string, corps: string): Promise<string> {
  const clef = await crypto.subtle.importKey(
    "raw",
    ENCODEUR.encode(cle),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const octets = await crypto.subtle.sign("HMAC", clef, ENCODEUR.encode(corps));

  return Array.from(new Uint8Array(octets))
    .map((o) => o.toString(16).padStart(2, "0"))
    .join("");
}

/// Compare deux chaînes en temps constant.
///
/// POURQUOI PAS `a === b`. Une comparaison ordinaire s'arrête au premier
/// caractère qui diffère, et le temps qu'elle met à répondre dit donc combien
/// de caractères étaient justes. Répétée, cette fuite laisse reconstruire une
/// signature valide octet par octet. On compare toujours toute la longueur.
///
/// Les longueurs différentes rendent faux tout de suite : elles ne révèlent
/// rien qu'un attaquant ne sache déjà — une signature SHA-256 en hexadécimal
/// fait toujours 64 caractères.
function memeSignature(a: string, b: string): boolean {
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

Deno.serve(async (requete: Request): Promise<Response> => {
  if (requete.method !== "POST") {
    return reponse({ message: "Cette fonction ne répond qu'en POST." }, 405);
  }

  const cleChargily = Deno.env.get("CHARGILY_SECRET_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const cleService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!cleChargily || !supabaseUrl || !cleService) {
    // 500 et non 200 : c'est une panne de configuration, et un webhook renvoyé
    // plus tard aboutira une fois la clé posée. L'acquitter maintenant le
    // perdrait pour de bon.
    console.error("Configuration absente : le webhook ne peut pas vérifier.");
    return reponse({ message: "Webhook non configuré." }, 500);
  }

  // LE CORPS BRUT, LU UNE SEULE FOIS. Tout part de là : c'est ce texte-là qui
  // a été signé, et c'est ce texte-là qu'on décodera ensuite.
  const brut = await requete.text();

  const signature = requete.headers.get("signature");
  if (!signature) {
    // « we will never send requests without a signature - a request without a
    // signature is always a fake request ». Rien n'est écrit, rien n'est lu.
    console.error("Webhook sans en-tête « signature » : ignoré.");
    return reponse({ message: "Signature absente." }, 401);
  }

  const attendue = await signatureDe(cleChargily, brut);
  if (!memeSignature(signature, attendue)) {
    // On ne dit PAS ce qu'on attendait. Le journal note l'incident, la réponse
    // ne donne aucune prise.
    console.error("Webhook à signature invalide : ignoré.");
    return reponse({ message: "Signature invalide." }, 401);
  }

  // À partir d'ici, et seulement à partir d'ici, le contenu est digne de foi.
  let evenement: Record<string, unknown>;
  try {
    evenement = JSON.parse(brut);
  } catch {
    console.error("Webhook signé mais illisible :", brut.slice(0, 500));
    return reponse({ message: "Corps illisible." }, 400);
  }

  const type = evenement["type"];
  const donnees = evenement["data"] as Record<string, unknown> | undefined;
  const checkoutId = donnees?.["id"];
  const montant = donnees?.["amount"];

  if (typeof type !== "string" || typeof checkoutId !== "string") {
    console.error("Webhook signé sans type ni checkout :", brut.slice(0, 500));
    return reponse({ message: "Événement incomplet." }, 400);
  }

  // ---------------------------------------------------------------------------
  // La base décide. Tout, et en une transaction.
  // ---------------------------------------------------------------------------

  const appel = await fetch(
    `${supabaseUrl}/rest/v1/rpc/confirmer_paiement_chargily`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: cleService,
        Authorization: `Bearer ${cleService}`,
      },
      body: JSON.stringify({
        p_checkout_id: checkoutId,
        p_type: type,
        // NULL plutôt que zéro quand le montant manque : `is distinct from`
        // le refusera, et « montant absent » ne doit pas se lire « 0 DA reçu ».
        p_montant: typeof montant === "number" ? montant : null,
        // Le corps brut, décodé — c'est raw_webhook du §6, gardé tel quel pour
        // le rapprochement comptable (§4.4, ADM-03).
        p_brut: evenement,
      }),
    },
  );

  if (!appel.ok) {
    // La base n'a pas répondu, ou a refusé. C'est une vraie panne : on rend un
    // 500 pour que Chargily renvoie l'événement. La fonction SQL, elle, ne lève
    // jamais sur un cas métier — si l'on passe ici, c'est autre chose.
    const detail = await appel.text().catch(() => "");
    console.error(
      `confirmer_paiement_chargily a échoué (${appel.status}) pour ` +
        `${checkoutId} : ${detail}`,
    );
    return reponse({ message: "Traitement impossible." }, 500);
  }

  const resultat = await appel.json();

  // Le journal dit ce qui s'est passé, en un mot — c'est ce qu'on relira le
  // jour où une cliente appellera pour dire qu'elle a payé.
  console.log(`${type} ${checkoutId} → ${resultat}`);

  return reponse({ resultat }, 200);
});
