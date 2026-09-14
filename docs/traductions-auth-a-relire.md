# Les traductions arabes des écrans d’authentification, à relire

> **RIEN DE CE DOCUMENT N’A ENCORE ÉTÉ RELU.** Les 52 traductions
> ci-dessous ont été écrites sans relecture par un locuteur natif. Elles
> sont en place et l’application les affiche — mais aucune n’a été
> validée.

**52 clés**, ajoutées au J23 pour les trois écrans d’authentification :
connexion, inscription, profil, et les messages d’erreur qu’ils montrent.

## Ce document est une VUE, pas une source

La traduction ne vit que dans `lib/core/l10n/app_ar.arb`. Ce fichier-ci en
est un reflet, pris pour être lu et annoté : le corriger ne corrigerait
rien dans l’application.

## Comment annoter

Écrivez votre version dans la colonne **correction**, et laissez-la vide
quand la traduction proposée vous convient. Une case vide veut donc dire
*bonne*, pas *pas encore regardée* — si vous vous arrêtez en chemin,
dites-le moi.

C’est de l’**arabe standard**, pas de la darja : ce sont des étiquettes
d’interface, pas une conversation. Le même choix qu’aux sept écrans du
parcours client.

Deux choses à surveiller plus que les autres :

* **les noms propres** — Amina, Karim, Supabase, CIB — restent en écriture
  latine au milieu d’une phrase arabe ; c’est la règle que suit déjà
  l’assistant ;
* **les chiffres** restent latins eux aussi (§10) : `0770 11 22 33` et
  `007_auth.sql` s’écrivent comme ici.

## Ce qui arrive ensuite

Vos corrections remplacent les valeurs de `app_ar.arb`, `flutter gen-l10n`
les reprend, et cet avertissement disparaît de l’en-tête — sur ce qui aura
été relu, et sur rien d’autre.

---

## Partagé par la connexion et l'inscription — 8 clés

Un seul champ, un seul libellé : ces huit textes s'affichent sur les deux écrans. Les relire une fois suffit.

| clé | français | arabe proposé | correction |
|---|---|---|---|
| `authAdresseEmail` | Adresse e-mail | البريد الإلكتروني | |
| `authMotDePasse` | Mot de passe | كلمة المرور | |
| `authAfficher` | Afficher | إظهار | |
| `authMasquer` | Masquer | إخفاء | |
| `authSeConnecter` | Se connecter | تسجيل الدخول | |
| `authCreerUnCompte` | Créer un compte | إنشاء حساب | |
| `authEmailManquant` | Entrez votre adresse e-mail. | أدخل بريدك الإلكتروني. | |
| `authEmailMalForme` | Cette adresse ne ressemble pas à une adresse e-mail. | هذا العنوان لا يبدو بريداً إلكترونياً. | |

---

## Écran de connexion — 7 clés

Les deux premiers boutons sont les comptes de démonstration du §4.1. Les prénoms — Amina, Karim — restent en écriture latine : ce sont des noms propres, et ceux du jeu de démonstration.

| clé | français | arabe proposé | correction |
|---|---|---|---|
| `connexionTitre` | Connexion | تسجيل الدخول | |
| `connexionSousTitre` | Retrouvez vos demandes et vos réservations. | استعِد طلباتك وحجوزاتك. | |
| `connexionDemoAmina` | Entrer comme Amina (cliente) | الدخول بحساب Amina (زبونة) | |
| `connexionDemoKarim` | Entrer comme Karim (propriétaire) | الدخول بحساب Karim (صاحب قاعة) | |
| `connexionOuAvecVotreCompte` | ou avec votre compte | أو بحسابك | |
| `connexionMotDePasseManquant` | Entrez votre mot de passe. | أدخل كلمة المرور. | |
| `connexionVersInscription` | Pas encore de compte ? Créer un compte | ليس لديك حساب بعد؟ أنشئ حساباً | |

---

## Écran d'inscription — 12 clés

`{email}` est remplacé par l'adresse que la personne vient de taper. Gardez-le tel quel dans la traduction, et placez-le où la phrase arabe le veut.

| clé | français | arabe proposé | correction |
|---|---|---|---|
| `inscriptionSousTitre` | Quelques secondes suffisent. Vous pourrez chercher une salle sans compte, mais il en faut un pour envoyer une demande. | لا يستغرق الأمر سوى ثوانٍ. يمكنك البحث عن قاعة بلا حساب، لكن إرسال طلب يحتاج إلى حساب. | |
| `inscriptionNomComplet` | Nom complet | الاسم الكامل | |
| `inscriptionNomManquant` | Entrez votre nom. | أدخل اسمك. | |
| `inscriptionNomTropCourt` | Ce nom est trop court. | هذا الاسم قصير جداً. | |
| `inscriptionSixCaracteres` | Six caractères au minimum. | ستة أحرف على الأقل. | |
| `inscriptionMotDePasseManquant` | Choisissez un mot de passe. | اختر كلمة مرور. | |
| `inscriptionCreerMonCompte` | Créer mon compte | أنشئ حسابي | |
| `inscriptionEspaceProprietaire` | Vous pourrez ouvrir votre espace propriétaire plus tard, depuis votre profil. | يمكنك فتح مساحة صاحب القاعة لاحقاً، من ملفك الشخصي. | |
| `inscriptionDejaUnCompte` | J’ai déjà un compte | لديّ حساب بالفعل | |
| `inscriptionVerifiezVotreBoite` | Vérifiez votre boîte mail | تحقّق من بريدك | |
| `inscriptionConfirmationEnvoyee` | Un message vient d’être envoyé à {email}. Ouvrez-le pour confirmer votre adresse, puis connectez-vous. | أُرسلت رسالة للتوّ إلى {email}. افتحها لتأكيد عنوانك، ثم سجّل الدخول. | |
| `inscriptionAllerALaConnexion` | Aller à la connexion | الذهاب إلى تسجيل الدخول | |

---

## Écran de profil — 12 clés

`profilRoleClient` porte les deux genres parce qu'on ne demande pas lequel s'applique. `profilSansProfil` s'adresse à celui qui installe, pas au client : c'est une migration manquante.

| clé | français | arabe proposé | correction |
|---|---|---|---|
| `profilTitre` | Profil | الملف الشخصي | |
| `profilNonConnecteTitre` | Vous n’êtes pas connecté | لست مسجّل الدخول | |
| `profilNonConnecteTexte` | Continuez à chercher une salle sans compte. Il en faudra un pour envoyer une demande, échanger avec un propriétaire ou laisser un avis. | واصل البحث عن قاعة بلا حساب. ستحتاج إلى حساب لإرسال طلب، أو لمراسلة صاحب قاعة، أو لترك تقييم. | |
| `profilRoleProprietaire` | Propriétaire | صاحب قاعة | |
| `profilRoleClient` | Cliente ou client | زبونة أو زبون | |
| `profilRoleAdministration` | Administration | الإدارة | |
| `profilPublierMaSalle` | Publier ma salle | انشر قاعتك | |
| `profilMesSalles` | Mes salles | قاعاتي | |
| `profilTelephone` | Téléphone | الهاتف | |
| `profilNonRenseigne` | Non renseigné | غير مذكور | |
| `profilSeDeconnecter` | Se déconnecter | تسجيل الخروج | |
| `profilSansProfil` | Ce compte n’a pas de profil. La migration 007_auth.sql n’est probablement pas appliquée sur ce projet Supabase. | هذا الحساب لا يملك ملفاً شخصياً. على الأرجح أن الترحيل 007_auth.sql غير مطبَّق على مشروع Supabase هذا. | |

---

## Messages d'erreur — 13 clés

Ils sont choisis d'après le CODE que renvoie GoTrue, jamais d'après son texte anglais. `authRefusNonTraduit` est le repli : `{code}` et `{message}` viennent du serveur et restent en anglais — c'est voulu, voir `auth_messages.dart`.

| clé | français | arabe proposé | correction |
|---|---|---|---|
| `authIdentifiantsInvalides` | E-mail ou mot de passe incorrect. | البريد الإلكتروني أو كلمة المرور غير صحيحة. | |
| `authAdresseNonConfirmee` | Cette adresse n’a pas encore été confirmée. Ouvrez le message reçu par e-mail. | لم يُؤكَّد هذا العنوان بعد. افتح الرسالة التي وصلتك بالبريد. | |
| `authCompteIntrouvable` | Aucun compte ne correspond à cette adresse. | لا يوجد حساب بهذا العنوان. | |
| `authCompteExisteDeja` | Un compte existe déjà avec cette adresse. Connectez-vous. | يوجد حساب بهذا العنوان بالفعل. سجّل الدخول. | |
| `authMotDePasseTropFaible` | Mot de passe trop faible : il faut au moins six caractères. | كلمة المرور ضعيفة: يلزم ستة أحرف على الأقل. | |
| `authMemeMotDePasse` | Le nouveau mot de passe est identique à l’ancien. | كلمة المرور الجديدة مطابقة للقديمة. | |
| `authAdresseInvalide` | Adresse e-mail invalide. | بريد إلكتروني غير صالح. | |
| `authTropDeTentatives` | Trop de tentatives. Patientez une minute avant de réessayer. | محاولات كثيرة. انتظر دقيقة قبل إعادة المحاولة. | |
| `authCompteSuspendu` | Ce compte est suspendu. Contactez-nous. | هذا الحساب موقوف. تواصل معنا. | |
| `authInscriptionsFermees` | Les inscriptions sont fermées pour le moment. | التسجيل مغلق في الوقت الحالي. | |
| `authEmailDesactive` | La connexion par e-mail est désactivée sur ce projet Supabase. | تسجيل الدخول بالبريد الإلكتروني معطَّل في مشروع Supabase هذا. | |
| `authCaptchaEchoue` | La vérification anti-robot a échoué. Réessayez. | فشل التحقق من أنك لست روبوتاً. أعد المحاولة. | |
| `authRefusNonTraduit` | Connexion impossible ({code}) : {message} | تعذّر تسجيل الدخول ({code}): {message} | |

