import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ferha/core/router/app_router.dart';
import 'package:ferha/core/router/routes.dart';

/// Les trois écrans de la salle se consultent sans compte (§3).
///
/// Ce test ne regarde pas ce qu'ils affichent : il vérifie que le routeur les
/// atteint, sans redirection qui les renverrait vers l'accueil ou la connexion.
/// C'est l'invariant qu'une `redirect` globale casserait sans bruit — l'écran
/// deviendrait blanc et l'adresse retomberait sur `/accueil`.
void main() {
  late ProviderContainer conteneur;

  setUp(() => conteneur = ProviderContainer());
  tearDown(() => conteneur.dispose());

  const id = '6f1a2b3c-0000-4000-8000-000000000001';

  void verifie(String nom, String emplacement) {
    test('$nom se résout sans redirection', () {
      final trouve = conteneur
          .read(routerProvider)
          .configuration
          .findMatch(Uri.parse(emplacement));

      expect(trouve.error, isNull);
      expect(trouve.uri.path, Uri.parse(emplacement).path);
    });
  }

  verifie('la fiche', '${FerhaRoutes.salleDe(id)}?creneau=soir&invites=200');
  verifie('la galerie', FerhaRoutes.galerieDe(id));
  verifie('le calendrier', '${FerhaRoutes.calendrierDe(id)}?creneau=midi');

  // L'écran de demande aussi : c'est LUI qui réclame la connexion, au moment
  // d'envoyer, et pas le routeur avant d'y entrer. Un visiteur non connecté
  // doit pouvoir composer sa demande de bout en bout — choisir son type
  // d'événement, ses invités, ses options, voir le devis se recalculer — et
  // n'être arrêté qu'au bouton « Envoyer ». Une `redirect` posée sur cette
  // route lui ferait tout perdre avant d'avoir vu un seul prix.
  verifie(
    'la demande',
    '${FerhaRoutes.demandeDe(id)}?creneau=soir&date=2027-08-14&invites=320',
  );
  verifie(
    'la confirmation',
    '${FerhaRoutes.demandeEnvoyee}?ref=3f2a1b4c-0000-4000-8000-000000000001',
  );

  // Le suivi des réservations non plus n'a pas de redirection : c'est le profil
  // qui n'offre l'entrée qu'à un compte connecté, et `client_bookings()` qui
  // refuse un appel sans session. Une `redirect` ferait un troisième gardien
  // pour la même règle, et c'est celui qu'on oublierait de retirer.
  verifie('le suivi des réservations', FerhaRoutes.mesReservations);
}
