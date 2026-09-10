import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ferha/core/preferences/preferences_affichage.dart';
import 'package:ferha/features/auth/auth_providers.dart';
import 'package:ferha/features/owner/demande_detail.dart';
import 'package:ferha/features/owner/demande_en_attente.dart';
import 'package:ferha/features/owner/indicateurs_salle.dart';
import 'package:ferha/features/owner/owner_messages.dart';
import 'package:ferha/features/owner/owner_providers.dart';
import 'package:ferha/features/owner/owner_repository.dart';
import 'package:ferha/features/owner/salle_du_proprietaire.dart';

import 'owner_fakes.dart';

/// Répondre à une demande, et ce qu'il faut remettre d'aplomb derrière.
///
/// LE TEST QUI COMPTE ICI EST CELUI DU COMPTEUR. Accepter une demande est une
/// ligne de code et se vérifie en une assertion ; ce qui se casse ensuite si
/// l'on s'arrête là est bien moins visible. Le compte du sélecteur — « Salle
/// El Bahia · 3 » — vient d'`owner_venues()`, une lecture qui ignore tout de ce
/// qui vient de se passer. Sans le rafraîchissement, le propriétaire lit « 3 »
/// au-dessus d'une file qui n'en montre plus que deux, et croit en avoir perdu
/// une.
///
/// CE FICHIER NE VÉRIFIE AUCUN DROIT, et c'est volontaire. « Un propriétaire
/// qui n'est pas le bon ne peut rien » se vérifie là où la règle vit, c'est-à-
/// dire en SQL : `supabase/tests/003_reponse_proprietaire.sql`. Un test Dart
/// qui monterait un faux dépôt ne prouverait que ce que le faux dépôt veut bien
/// dire.
void main() {
  const bahia = '5a11e000-0000-4000-a000-000000000001';
  const ennour = '5a11e000-0000-4000-a000-000000000002';

  ({ProviderContainer container, DepotDeTest depot}) espace({
    int demandesAvant = 3,
  }) {
    final depot = DepotDeTest(
      sallesRendues: <SalleDuProprietaire>[
        salleDeTest(id: bahia, demandesEnAttente: demandesAvant),
        salleDeTest(id: ennour, nom: 'Salle Ennour'),
      ],
      indicateursRendus: <String, IndicateursSalle>{bahia: indicateursDeTest()},
      demandesRendues: <String, List<DemandeEnAttente>>{
        bahia: <DemandeEnAttente>[demandeDeTest(id: '1')],
      },
      detailsRendus: <String, DemandeDetail>{
        'bkg-1': detailDeTest(id: '1', venueId: bahia),
      },
    );

    final container = ProviderContainer(
      overrides: [
        estConnecteProvider.overrideWithValue(true),
        preferencesAffichageProvider.overrideWithValue(
          PreferencesEnMemoire(bahia),
        ),
        ownerRepositoryProvider.overrideWithValue(depot),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, depot: depot);
  }

  group('Le geste lui-même', () {
    test('accepter transmet la demande, et rien de plus', () async {
      final (:container, :depot) = espace();
      await container.read(espaceProprietaireProvider.future);

      await container
          .read(reponseADemandeServiceProvider)
          .accepter(depot.detailsRendus['bkg-1']!);

      expect(depot.acceptees, <String>['bkg-1']);
      // AUCUN ACOMPTE N'EST ENVOYÉ. `accepter_demande()` applique
      // `deposit_rate()` au devis déjà en base : le taux du §5.3 vit à un seul
      // endroit, et ce n'est pas le client Flutter.
      expect(depot.refusees, isEmpty);
    });

    test('refuser transmet le motif', () async {
      final (:container, :depot) = espace();
      await container.read(espaceProprietaireProvider.future);

      await container
          .read(reponseADemandeServiceProvider)
          .refuser(depot.detailsRendus['bkg-1']!, motif: 'Salle en travaux');

      expect(depot.refusees.single.id, 'bkg-1');
      expect(depot.refusees.single.motif, 'Salle en travaux');
    });

    test('refuser sans motif reste un refus', () async {
      final (:container, :depot) = espace();
      await container.read(espaceProprietaireProvider.future);

      await container
          .read(reponseADemandeServiceProvider)
          .refuser(depot.detailsRendus['bkg-1']!);

      expect(depot.refusees.single.motif, isNull);
    });

    test('une erreur remonte à l’écran, elle n’est pas avalée', () async {
      final (:container, :depot) = espace();
      await container.read(espaceProprietaireProvider.future);
      depot.erreurDeReponse = const PostgrestException(
        message: 'Ce créneau a été confirmé entre-temps.',
        code: 'PT409',
        hint: 'FE013',
      );

      await expectLater(
        container
            .read(reponseADemandeServiceProvider)
            .accepter(depot.detailsRendus['bkg-1']!),
        throwsA(isA<PostgrestException>()),
      );

      // Et rien n'a été rafraîchi : il n'y avait rien à rafraîchir.
      expect(depot.appelsSalles, 1);
    });
  });

  group('Ce que la réponse remet d’aplomb', () {
    test('le compteur du sélecteur est redemandé, et il change', () async {
      final (:container, :depot) = espace();
      final avant = await container.read(espaceProprietaireProvider.future);
      expect(avant.salleCourante?.demandesEnAttente, 3);
      expect(depot.appelsSalles, 1);

      // La base répondra désormais « 2 » : c'est ce que fait `owner_venues()`
      // une fois la demande sortie de la file.
      depot.sallesRendues = <SalleDuProprietaire>[
        salleDeTest(id: bahia, demandesEnAttente: 2),
        salleDeTest(id: ennour, nom: 'Salle Ennour'),
      ];

      await container
          .read(reponseADemandeServiceProvider)
          .accepter(depot.detailsRendus['bkg-1']!);

      expect(depot.appelsSalles, 2, reason: 'La liste n’a pas été redemandée.');
      expect(
        container
            .read(espaceProprietaireProvider)
            .value
            ?.salleCourante
            ?.demandesEnAttente,
        2,
      );
    });

    test('la salle regardée ne change pas sous les pieds', () async {
      final (:container, :depot) = espace();
      await container.read(espaceProprietaireProvider.future);
      await container.read(espaceProprietaireProvider.notifier).choisir(ennour);

      await container
          .read(reponseADemandeServiceProvider)
          .accepter(depot.detailsRendus['bkg-1']!);

      expect(
        container.read(espaceProprietaireProvider).value?.salleCouranteId,
        ennour,
      );
    });

    test('le tableau de bord ne repasse pas par son squelette', () async {
      final (:container, :depot) = espace();
      await container.read(espaceProprietaireProvider.future);

      // POURQUOI CE TEST EXISTE. `ref.invalidate()` aurait été la façon
      // évidente de rafraîchir le compteur, et elle aurait marché — au prix
      // d'un retour à `AsyncLoading`, donc du squelette et du titre qui
      // disparaît, une demi-seconde après chaque réponse. On recharge les
      // données sans toucher à l'enveloppe ; si quelqu'un remplace un jour
      // `rafraichir()` par une invalidation, c'est ici que ça se verra.
      final etats = <AsyncValue<EspaceProprietaire>>[];
      container.listen(
        espaceProprietaireProvider,
        (_, suivant) => etats.add(suivant),
      );

      await container
          .read(reponseADemandeServiceProvider)
          .accepter(depot.detailsRendus['bkg-1']!);

      expect(etats, isNotEmpty, reason: 'Le compteur n’a pas bougé du tout.');
      expect(
        etats.whereType<AsyncLoading<EspaceProprietaire>>(),
        isEmpty,
        reason: 'L’écran est retombé sur son squelette après la réponse.',
      );
    });

    test('la file et les chiffres du mois sont redemandés', () async {
      final (:container, :depot) = espace();
      await container.read(espaceProprietaireProvider.future);

      // On les lit une première fois, comme le ferait l'écran, puis on
      // s'abonne : sans abonnement, un fournisseur `autoDispose` se referme
      // aussitôt et l'invalidation ne se verrait pas.
      final abonnements = <ProviderSubscription<Object?>>[
        container.listen(demandesEnAttenteProvider(bahia), (_, _) {}),
        container.listen(indicateursProvider(bahia), (_, _) {}),
        container.listen(detailDemandeProvider('bkg-1'), (_, _) {}),
      ];
      await container.read(demandesEnAttenteProvider(bahia).future);
      await container.read(indicateursProvider(bahia).future);
      await container.read(detailDemandeProvider('bkg-1').future);

      expect(depot.appelsDemandes, 1);
      expect(depot.appelsIndicateurs, 1);
      expect(depot.appelsDetail, 1);

      await container
          .read(reponseADemandeServiceProvider)
          .accepter(depot.detailsRendus['bkg-1']!);

      await container.read(demandesEnAttenteProvider(bahia).future);
      await container.read(indicateursProvider(bahia).future);
      await container.read(detailDemandeProvider('bkg-1').future);

      // La file perd une ligne, la part des demandes acceptées du mois bouge,
      // et le détail gagne son acompte et son échéance de 72 h.
      expect(depot.appelsDemandes, 2);
      expect(depot.appelsIndicateurs, 2);
      expect(depot.appelsDetail, 2);

      for (final abonnement in abonnements) {
        abonnement.close();
      }
    });
  });

  group('Les refus de la base deviennent des phrases', () {
    String phrase(String hint) => messageErreurReponse(
      PostgrestException(message: 'peu importe', code: 'PT409', hint: hint),
    );

    test('FE013 dit la course perdue, et ce qui reste possible', () {
      final message = phrase('FE013');
      expect(message, contains('confirmé entre-temps'));
      // La phrase ne laisse pas le propriétaire devant un mur : refuser reste
      // possible, et c'est ce qu'il lui reste à faire.
      expect(message, contains('refuser'));
    });

    test('FE012 ne gronde personne', () {
      expect(phrase('FE012'), contains('déjà reçu une réponse'));
    });

    test('FE011 et FE010 sont traduits aussi', () {
      expect(phrase('FE011'), contains('vos salles'));
      expect(phrase('FE010'), contains('session'));
    });

    test('aucun code Ferha n’atteint l’écran', () {
      for (final code in <String>['FE010', 'FE011', 'FE012', 'FE013']) {
        expect(
          phrase(code),
          isNot(contains('FE')),
          reason: 'Le code « $code » se lit tel quel à l’écran.',
        );
      }
    });

    test('un hint inconnu retombe sur la traduction commune', () {
      // On ne veut surtout pas d'une phrase inventée : mieux vaut le message
      // d'origine, que quelqu'un pourra reconnaître, qu'un « une erreur est
      // survenue » qui ne dit rien.
      expect(
        messageErreurReponse(
          const PostgrestException(
            message: 'connexion perdue',
            code: 'XX000',
            hint: 'FE999',
          ),
        ),
        isNot(contains('FE999')),
      );
    });
  });
}
