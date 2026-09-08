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
