import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ferha/core/preferences/preferences_affichage.dart';
import 'package:ferha/features/auth/auth_providers.dart';
import 'package:ferha/features/owner/owner_providers.dart';
import 'package:ferha/features/owner/owner_repository.dart';
import 'package:ferha/features/owner/salle_du_proprietaire.dart';

import 'owner_fakes.dart';

/// La salle retenue d'une ouverture à l'autre (§4.3, OWN-08).
///
/// DEUX CONTENEURS RIVERPOD SUCCESSIFS, C'EST DEUX OUVERTURES DE
/// L'APPLICATION. Le premier choisit, le second doit retrouver — et entre les
/// deux, seules les préférences survivent, exactement comme un `localStorage`
/// survit à un rechargement de page. C'est la seule façon de vérifier qu'on
/// retient vraiment, sans plateforme à simuler.
///
/// LE SECOND TEST QUI COMPTE EST CELUI DE LA SALLE DISPARUE. Un identifiant
/// traîne dans un fichier en clair sur l'appareil ; il peut désigner la salle
/// d'un autre compte connecté avant, ou une salle vendue depuis. La liste que
/// rend la base fait foi, toujours, et la préférence se fait oublier.
void main() {
  const bahia = '5a11e000-0000-4000-a000-000000000001';
  const andalouses = '5a11e000-0000-4000-a000-000000000002';
  const ennour = '5a11e000-0000-4000-a000-000000000003';

  final quatreSalles = <SalleDuProprietaire>[
    salleDeTest(id: andalouses, nom: 'Résidence Les Andalouses'),
    salleDeTest(id: bahia, nom: 'Salle El Bahia', demandesEnAttente: 3),
    salleDeTest(id: ennour, nom: 'Salle Ennour'),
  ];

  /// Une ouverture de l'application, sur des préférences qui lui survivent.
  ProviderContainer ouverture({
    required PreferencesEnMemoire preferences,
    required OwnerRepository depot,
    bool connecte = true,
  }) {
    final container = ProviderContainer(
      overrides: [
        estConnecteProvider.overrideWithValue(connecte),
        preferencesAffichageProvider.overrideWithValue(preferences),
        ownerRepositoryProvider.overrideWithValue(depot),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('sans rien de retenu, la première salle de la liste s’ouvre', () async {
    final preferences = PreferencesEnMemoire();
    final container = ouverture(
      preferences: preferences,
      depot: DepotDeTest(sallesRendues: quatreSalles),
    );

    final espace = await container.read(espaceProprietaireProvider.future);

    // La première DE LA LISTE, et `owner_venues()` trie par nom : l'ordre est
    // stable d'une ouverture à l'autre, ce qui compte quand c'est lui qui sert
    // de valeur par défaut.
    expect(espace.salleCouranteId, andalouses);
    expect(espace.salleCourante?.nom, 'Résidence Les Andalouses');
    expect(espace.plusieursSalles, isTrue);
    // Le défaut est retenu tout de suite : sans quoi la question « quelle
    // salle ? » se reposerait à chaque démarrage, et un simple changement de
    // nom — qui change l'ordre alphabétique — ferait basculer Karim sur une
    // autre salle sans qu'il ait rien demandé.
    expect(preferences.retenue, andalouses);
  });

  test('la salle choisie se retrouve à l’ouverture suivante', () async {
    final preferences = PreferencesEnMemoire();
    final depot = DepotDeTest(sallesRendues: quatreSalles);

    final premiere = ouverture(preferences: preferences, depot: depot);
    await premiere.read(espaceProprietaireProvider.future);
    await premiere.read(espaceProprietaireProvider.notifier).choisir(bahia);

    expect(
      premiere.read(espaceProprietaireProvider).value?.salleCouranteId,
      bahia,
    );
    expect(preferences.retenue, bahia);

    // L'application se ferme, et se rouvre. Rien ne passe d'un conteneur à
    // l'autre — sauf le fichier de préférences.
    premiere.dispose();

    final seconde = ouverture(preferences: preferences, depot: depot);
    final espace = await seconde.read(espaceProprietaireProvider.future);

    expect(espace.salleCouranteId, bahia);
    expect(espace.salleCourante?.nom, 'Salle El Bahia');
  });

  test('une salle retenue qui n’est plus la vôtre se fait oublier', () async {
    // L'identifiant est bien formé, il désigne juste une salle que la base ne
    // rend plus. Le croire ouvrirait un tableau de bord sur rien — ou, si la
    // salle appartient à quelqu'un d'autre, sur un refus de `owner_dashboard()`
    // que l'écran n'aurait aucun moyen d'expliquer.
    final preferences = PreferencesEnMemoire(
      '5a11e000-0000-4000-a000-000000000999',
    );

    final container = ouverture(
      preferences: preferences,
      depot: DepotDeTest(sallesRendues: quatreSalles),
    );
    final espace = await container.read(espaceProprietaireProvider.future);

    expect(espace.salleCouranteId, andalouses);
    // Et l'identifiant mort ne reste pas sur l'appareil à être réexaminé à
    // chaque démarrage.
    expect(preferences.retenue, andalouses);
  });

  test('retenir la même salle n’écrit rien de plus', () async {
    final preferences = PreferencesEnMemoire(bahia);
    final container = ouverture(
      preferences: preferences,
      depot: DepotDeTest(sallesRendues: quatreSalles),
    );

    await container.read(espaceProprietaireProvider.future);
    expect(preferences.ecritures, 0);

    // Rechoisir la salle déjà ouverte n'écrit pas non plus : le sélecteur se
    // referme, et rien ne se passe.
    await container.read(espaceProprietaireProvider.notifier).choisir(bahia);
    expect(preferences.ecritures, 0);
  });

  test('on ne peut pas choisir une salle absente de la liste', () async {
    final preferences = PreferencesEnMemoire();
    final container = ouverture(
      preferences: preferences,
      depot: DepotDeTest(sallesRendues: quatreSalles),
    );
    await container.read(espaceProprietaireProvider.future);

    await container
        .read(espaceProprietaireProvider.notifier)
        .choisir('5a11e000-0000-4000-a000-000000000999');

    // L'état ne bouge pas, et l'identifiant inconnu n'est pas retenu : le
    // sélecteur ne propose que des salles de la liste, mais l'état refuse
    // quand même de sortir d'elle.
    expect(
      container.read(espaceProprietaireProvider).value?.salleCouranteId,
      andalouses,
    );
    expect(preferences.retenue, andalouses);
  });

  test('un propriétaire sans salle n’ouvre rien, et ne retient rien', () async {
    final preferences = PreferencesEnMemoire();
    final container = ouverture(preferences: preferences, depot: DepotDeTest());

    final espace = await container.read(espaceProprietaireProvider.future);

    expect(espace.salles, isEmpty);
    expect(espace.salleCourante, isNull);
    expect(espace.plusieursSalles, isFalse);
    // Rien à retenir, donc rien d'écrit.
    expect(preferences.retenue, isNull);
    expect(preferences.ecritures, 0);
  });

  test('déconnecté, on ne demande même pas la liste', () async {
    final preferences = PreferencesEnMemoire(bahia);
    final depot = DepotDeTest(sallesRendues: quatreSalles);

    final container = ouverture(
      preferences: preferences,
      depot: depot,
      connecte: false,
    );
    final espace = await container.read(espaceProprietaireProvider.future);

    expect(espace.salles, isEmpty);
    expect(depot.appelsSalles, 0);
    // La préférence n'est pas effacée pour autant : elle attend la prochaine
    // connexion, qui est très probablement la même personne sur le même
    // téléphone.
    expect(preferences.retenue, bahia);
  });
}
