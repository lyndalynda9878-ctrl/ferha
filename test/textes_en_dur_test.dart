import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// LE TEST QUI EMPÊCHE LA TRADUCTION DE SE DÉFAIRE.
///
/// Traduire un écran est un travail qui se fait une fois ; le garder traduit est
/// un travail qui se refait à chaque modification. Une phrase française rajoutée
/// en dur dans `venue_screen.dart` un mardi ne se voit pas : elle s'affiche
/// correctement en français, l'analyse ne dit rien, et personne ne rouvre
/// l'application en arabe avant longtemps. C'est le genre de régression qui ne
/// se découvre qu'à la démonstration.
///
/// Ce test lit donc les fichiers traduits COMME DU TEXTE et cherche les
/// chaînes qui ressemblent à de la prose. Il ne comprend pas le Dart, et il n'a
/// pas à le comprendre : une phrase destinée à être lue a une forme
/// reconnaissable — des lettres, et une espace ou un accent.
///
/// =============================================================================
/// CE QU'IL CONSIDÈRE COMME UNE PHRASE
///
/// Après avoir retiré les commentaires, les lignes d'import et les
/// interpolations — ce qui est déjà traduit n'a pas à l'être deux fois —, une
/// chaîne est suspecte si :
///
///   * elle contient une lettre ET (une espace OU un accent français) :
///     « Aucune salle publiée ici », « Réessayer » ;
///   * ou elle est UN SEUL MOT capitalisé d'au moins quatre lettres :
///     « Continuer », « Options », « Parking ». C'est la forme d'un libellé de
///     bouton, et c'est le cas que la première règle laisserait passer.
///
/// Ne sont donc PAS suspects : les codes (FE001, midi, cib), les chemins
/// (venue-photos), la ponctuation, les formats de date.
///
/// =============================================================================
/// LA LISTE DES TOLÉRÉS EST COURTE, ET CHACUN Y EST EXPLIQUÉ
///
/// Une exception sans raison écrite est une porte ouverte. S'il en faut une
/// nouvelle, elle s'ajoute avec sa phrase — et si la phrase est difficile à
/// écrire, c'est que la chaîne avait sa place dans un fichier ARB.
void main() {
  /// Les fichiers traduits — les sept écrans du parcours client (§10) et les
  /// trois écrans d'authentification.
  ///
  /// LES WIDGETS PARTAGÉS EN FONT PARTIE. `etats.dart` porte les états vides et
  /// les erreurs de quatre de ces écrans, `grille_calendrier.dart` le titre du
  /// mois : les exclure laisserait la moitié des phrases hors du contrôle.
  ///
  /// LES TRADUCTEURS DE REFUS AUSSI. `booking_messages.dart` et
  /// `acompte_messages.dart` ne dessinent rien, mais toute phrase qu'un client
  /// lit après avoir appuyé sur « Envoyer » ou « Payer » sort de là.
  const ecrans = <String>[
    // Écran 1 — accueil / recherche
    'lib/features/search/accueil_screen.dart',
    // Écran 2 — résultats
    'lib/features/search/resultats_screen.dart',
    'lib/features/search/widgets/venue_card.dart',
    'lib/features/search/widgets/etats.dart',
    // Écran 3 — fiche salle
    'lib/features/venue/venue_screen.dart',
    // Écran 4 — calendrier
    'lib/features/venue/calendrier_screen.dart',
    'lib/core/widgets/grille_calendrier.dart',
    // Écran 5 — la demande, et ce qui la suit
    'lib/features/booking/demande_screen.dart',
    'lib/features/booking/demande_envoyee_screen.dart',
    'lib/features/booking/booking_messages.dart',
    // Écran 6 — l'acompte
    'lib/features/booking/acompte_screen.dart',
    'lib/features/booking/acompte_messages.dart',
    'lib/features/booking/widgets/compte_a_rebours.dart',
    // Ce que les six partagent
    'lib/core/l10n/message_erreur.dart',
    'lib/core/validation/telephone.dart',
    // Les trois écrans d'authentification, et ce qu'ils partagent.
    'lib/features/auth/connexion_screen.dart',
    'lib/features/auth/inscription_screen.dart',
    'lib/features/auth/profil_screen.dart',
    'lib/features/auth/widgets/auth_scaffold.dart',
    'lib/features/auth/auth_messages.dart',
  ];

  /// Ce qu'on laisse passer, et pourquoi.
  const tolerees = <String, String>{
    'failed host lookup':
        'Un morceau de message d’exception ANGLAIS, cherché dans le texte '
        'd’une erreur pour reconnaître une panne de réseau. Personne ne le '
        'lit : c’est une aiguille, pas une phrase.',
    'connection refused': 'La même chose — voir « failed host lookup ».',
  };

  /// Les fonctions de mise en forme qui ne savent écrire qu'en français.
  ///
  /// Elles restent dans le dépôt pour les écrans du propriétaire, qui ne sont
  /// pas traduits. Les appeler depuis un écran traduit donnerait une date
  /// française au milieu d'une page arabe — une faute que le contrôle des
  /// chaînes ne verrait pas, puisqu'il n'y a aucune chaîne à voir.
  ///
  /// `messageErreurAuthEnFrancais` est dans la liste pour la même raison :
  /// c'est le repli des écrans NON traduits, et il n'a rien à faire dans un
  /// écran qui, lui, connaît sa langue.
  const interdits = <String>[
    'dateEnFrancais',
    'dateCourteEnFrancais',
    'jourEnFrancais',
    'moisEnFrancais',
    'nomMois',
    'montantEnDinars',
    'libelleCreneau',
    'messageErreurAuthEnFrancais',
  ];

  /// Le fichier qui a le droit de nommer un interdit : celui qui le déclare.
  ///
  /// `auth_messages.dart` DÉFINIT `messageErreurAuthEnFrancais` — c'est son
  /// travail, et le motif du contrôle ne distingue pas un appel d'une
  /// déclaration. Une exception par nom, et elle dit où.
  const declarePar = <String, String>{
    'messageErreurAuthEnFrancais': 'lib/features/auth/auth_messages.dart',
  };

  const accents = 'àâäçéèêëîïôöùûüÿœæÀÂÄÇÉÈÊËÎÏÔÖÙÛÜŸŒÆ';
  final lettre = RegExp(r'[A-Za-zÀ-ɏ؀-ۿ]');
  final motCapitalise = RegExp(r'^[A-ZÀ-Ý][a-zà-ÿ]{3,}$');
  final interpolation = RegExp(r'\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*');

  // Les deux formes de chaîne Dart. Deux motifs plutôt qu'une alternance :
  // chacun est écrit dans l'autre guillemet, et se lit donc sans échappement.
  final chaineSimple = RegExp(r"'(?:[^'\\\n]|\\.)*'");
  final chaineDouble = RegExp(r'"(?:[^"\\\n]|\\.)*"');

  /// Le corps du fichier : sans commentaires, sans imports.
  ///
  /// LES FINS DE LIGNE SE NORMALISENT D'ABORD, et ce n'est pas une précaution
  /// de style. Le dépôt mêle LF et CRLF ; en CRLF il reste un retour chariot au
  /// bout de chaque ligne, et le point d'une expression régulière ne le
  /// traverse pas — le motif qui efface un commentaire s'arrêtait donc avant
  /// lui et n'effaçait rien. Les apostrophes des commentaires français
  /// passaient alors pour des guillemets, et le test accusait sa propre
  /// documentation.
  String corpsDe(String source) {
    final sansBlocs = source
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    return sansBlocs
        .split('\n')
        .where((l) {
          final nu = l.trimLeft();
          return !nu.startsWith('import ') && !nu.startsWith('export ');
        })
        // Les commentaires de ligne ET ceux de documentation : un `///` est un
        // `//` pour cette règle-là.
        .map((l) => l.replaceFirst(RegExp(r'(^|\s)//.*$'), ''))
        .join('\n');
  }

  bool ressembleAUnePhrase(String litteral) {
    final reste = litteral.replaceAll(interpolation, '').trim();
    if (reste.isEmpty) return false;
    if (tolerees.containsKey(reste)) return false;

    final aUneLettre = lettre.hasMatch(reste);
    final aUneEspace = reste.contains(' ');
    final aUnAccent = accents.split('').any(reste.contains);

    if (aUneLettre && (aUneEspace || aUnAccent)) return true;
    return motCapitalise.hasMatch(reste);
  }

  Set<String> textesEnDur(String corps) => <String>{
    ...chaineSimple.allMatches(corps).map((m) => m.group(0)!),
    ...chaineDouble.allMatches(corps).map((m) => m.group(0)!),
  }.map((s) => s.substring(1, s.length - 1)).where(ressembleAUnePhrase).toSet();

  group('Les écrans traduits ne portent aucun texte en dur', () {
    for (final chemin in ecrans) {
      test(chemin.split('/').last, () {
        final fichier = File(chemin);
        expect(
          fichier.existsSync(),
          isTrue,
          reason:
              '$chemin a disparu. Si l’écran a été renommé, la liste de ce '
              'test doit suivre — sinon il ne contrôle plus rien, en silence.',
        );

        final enDur = textesEnDur(corpsDe(fichier.readAsStringSync()));

        expect(
          enDur,
          isEmpty,
          reason:
              'Texte en dur dans $chemin :\n'
              '${enDur.map((s) => '  « $s »').join('\n')}\n\n'
              'Ces six écrans se lisent en arabe (§10, CORE-03). Une phrase '
              'écrite ici ne se traduira pas : elle va dans '
              'lib/core/l10n/app_fr.arb et app_ar.arb, et l’écran l’appelle '
              'par AppLocalizations.of(context).',
        );
      });
    }

    for (final chemin in ecrans) {
      test('${chemin.split('/').last} — aucune mise en forme française', () {
        final corps = corpsDe(File(chemin).readAsStringSync());
        final trouves = interdits
            .where((f) => declarePar[f] != chemin)
            .where((f) => RegExp('\\b$f\\s*\\(').hasMatch(corps))
            .toList();

        expect(
          trouves,
          isEmpty,
          reason:
              '$chemin appelle ${trouves.join(', ')}, qui n’écrit qu’en '
              'français. Passez par FormatsFerha : ses dates, ses mois et ses '
              'montants suivent la langue de l’application.',
        );
      });
    }
  });

  group('Le détecteur lui-même', () {
    // UN DÉTECTEUR QU'ON NE VÉRIFIE PAS EST UN TEST QUI PASSE TOUJOURS. Ces
    // quatre cas-là disent ce qu'il attrape et ce qu'il laisse passer ; sans
    // eux, une expression régulière cassée rendrait le contrôle silencieux au
    // lieu de le rendre bruyant.
    test('attrape une phrase française', () {
      expect(textesEnDur("Text('Aucune salle publiée ici')"), isNotEmpty);
    });

    test('attrape un libellé d’un seul mot', () {
      expect(textesEnDur("child: Text('Continuer')"), isNotEmpty);
    });

    test('laisse passer un code et un chemin', () {
      expect(textesEnDur("case 'FE001': path('venue-photos')"), isEmpty);
    });

    test('laisse passer ce qui n’est que de la ponctuation', () {
      expect(textesEnDur(r"join(' · ') + ' ${textes.devise}'"), isEmpty);
    });

    test('ne lit pas les commentaires', () {
      // C'est le cas qui a fait échouer ce test la première fois : une
      // apostrophe française dans un commentaire ressemble à un guillemet.
      expect(
        textesEnDur(corpsDe("  /// on tient jusqu'à demain soir, l'autre\n")),
        isEmpty,
      );
    });
  });

  test('la liste des tolérés reste courte, et chacun y est expliqué', () {
    expect(tolerees.length, lessThanOrEqualTo(5));
    for (final raison in tolerees.values) {
      expect(raison.length, greaterThan(30));
    }
  });
}
