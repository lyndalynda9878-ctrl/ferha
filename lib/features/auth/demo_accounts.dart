/// Les deux comptes de démonstration proposés en un tap (§4.1, CORE-01).
///
/// Le mot de passe est en clair, et c'est voulu : ce sont des comptes publics,
/// posés par `supabase/seed/003_demo_accounts.sql`, sur une base de
/// démonstration, sans aucune donnée réelle. Le cacher ne protégerait rien.
///
/// SEUL ENDROIT du code Flutter qui connaît ces identifiants. Si vous
/// recréez les comptes autrement — la solution de repli décrite en bas du
/// fichier de seed — c'est ici, et ici seulement, qu'il faut les corriger.
library;

/// Un compte de démonstration.
typedef CompteDemo = ({String email, String motDePasse, String libelle});

/// Amina — cliente, aucune salle. Le point de vue par défaut : quelqu'un qui
/// cherche une salle.
const CompteDemo compteAmina = (
  email: 'amina@demo.ferha.dz',
  motDePasse: 'demo1234',
  libelle: 'Entrer comme Amina (cliente)',
);

/// Karim — propriétaire de quatre salles du catalogue de démonstration. C'est
/// le même compte que celui de `seed/001_demo_venues.sql` : en se connectant,
/// il voit ses salles, pas un espace vide.
const CompteDemo compteKarim = (
  email: 'karim.belhadj@demo.ferha.dz',
  motDePasse: 'demo1234',
  libelle: 'Entrer comme Karim (propriétaire)',
);

/// Le préfixe d'identifiant des comptes de démonstration.
///
/// C'EST LA CONVENTION DU DÉCOR, PAS UNE INVENTION D'ICI : `d0000000-…` pour
/// une personne de démonstration, posée par
/// `supabase/seed/003_demo_accounts.sql` et reprise telle quelle par le ménage
/// du décor (`supabase/migrations/035_le_decor_se_remet_en_place.sql` et
/// `036_les_personnes_du_decor.sql`) et par le déclencheur qui interdit le
/// téléphone :
///
///     supabase/migrations/038_pas_de_telephone_en_demonstration.sql
///       profiles_pas_de_telephone_en_demonstration()
///
/// LES DEUX EXEMPLAIRES DOIVENT S'ACCORDER. Celui-ci décide de ce que l'écran
/// DIT ; celui de la base décide de ce qui se PASSE. Si l'un changeait sans
/// l'autre, l'écran promettrait une chose et la base en ferait une autre —
/// c'est exactement le mensonge que 038 répare. Le commentaire symétrique se
/// trouve dans l'en-tête de cette migration.
const String prefixeCompteDemonstration = 'd0000000-';

/// Vrai si [idUtilisateur] est l'un des comptes de démonstration partagés.
///
/// Sert à DIRE à la personne que son numéro ne sera pas conservé (écran 5).
/// Ce n'est pas une protection : la protection est le déclencheur de 038, en
/// base, qui met `phone` à NULL quoi qu'affiche l'application.
bool estCompteDeDemonstration(String? idUtilisateur) =>
    idUtilisateur != null &&
    idUtilisateur.startsWith(prefixeCompteDemonstration);
