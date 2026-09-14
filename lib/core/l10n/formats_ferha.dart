/// Les formats qui changent avec la langue — et les deux qui n'en changent pas.
///
/// =============================================================================
/// LES CHIFFRES RESTENT LATINS, EN ARABE COMME EN FRANÇAIS
///
/// C'est le premier des trois pièges du §10 des maquettes, et il ne se règle pas
/// tout seul : `intl` connaît les chiffres arabes-indiens — ٠١٢٣٤٥٦٧٨٩ — et
/// `NumberFormat` en locale `ar` les sort de lui-même. Un prix écrit
/// « ١٨٠ ٠٠٠ دج » serait typographiquement irréprochable et pratiquement
/// illisible : en Algérie, les prix, les numéros de téléphone et les dates
/// s'écrivent en chiffres latins, sur les devantures comme sur les factures.
///
/// D'où la règle de ce fichier : AUCUN NOMBRE NE PASSE PAR `intl`. Ils sont mis
/// en forme à la main, à partir de `toString()`, qui rend toujours des chiffres
/// ASCII quelle que soit la langue de l'application. Ce n'est pas un raccourci
/// pris faute de mieux — c'est la seule façon d'être sûr que la langue ne peut
/// pas changer un montant.
///
/// Ce qui se traduit d'un montant, c'est sa DEVISE, et elle seule : `DA`
/// devient `دج` par la clé `montantEnDinars`.
///
/// =============================================================================
/// L'ESPACEMENT DES CAPITALES NE VAUT PAS POUR L'ARABE
///
/// Les intitulés de section des maquettes sont des capitales espacées —
/// `letterSpacing: 1.2`. En arabe, les lettres d'un mot SE LIENT : écarter les
/// lettres ne donne pas un titre aéré, cela casse les liaisons et rend le mot
/// méconnaissable, comme un mot latin dont on aurait retiré les jambages.
///
/// [espacementDesCapitales] rend donc l'espacement de la charte en écriture
/// latine, et zéro en arabe. Ce n'est pas une valeur de charte — c'est une
/// propriété de l'écriture, au même titre que le sens de lecture.
library;

import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

/// Les formats de Ferha pour une langue donnée.
///
/// À construire depuis le contexte — `FormatsFerha.de(context)` — et à garder
/// le temps d'un `build`, jamais plus : une instance retient la langue qu'elle
/// avait à sa naissance.
@immutable
class FormatsFerha {
  /// Crée les formats à partir des textes traduits.
  const FormatsFerha(this._textes);

  /// Les formats de la langue courante.
  factory FormatsFerha.de(BuildContext context) =>
      FormatsFerha(AppLocalizations.of(context));

  final AppLocalizations _textes;

  // ---------------------------------------------------------------------------
  // Les nombres — en chiffres latins, voir l'en-tête
  // ---------------------------------------------------------------------------

  /// « 180 000 » — séparateur d'espace fine insécable entre les milliers.
  ///
  /// LE SÉPARATEUR NE CHANGE PAS AVEC LA LANGUE. U+202F est une espace, pas un
  /// signe : elle groupe les chiffres sans rien ajouter à lire, et elle fait ce
  /// travail aussi bien dans une phrase arabe que dans une française. Une
  /// virgule ou un point, eux, auraient chacun un sens différent selon la
  /// langue — et un prix n'a pas le droit d'être ambigu.
  String nombre(num valeur) {
    final entier = valeur.round().toString();
    final tampon = StringBuffer();
    for (var i = 0; i < entier.length; i++) {
      if (i > 0 && (entier.length - i) % 3 == 0) tampon.write(' ');
      tampon.write(entier[i]);
    }
    return tampon.toString();
  }

  /// « 180 000 DA », « 180 000 دج ». Le nombre en chiffres latins, la devise
  /// dans la langue de l'application.
  String montant(num valeur) => _textes.montantEnDinars(nombre(valeur));

  // ---------------------------------------------------------------------------
  // Les dates
  // ---------------------------------------------------------------------------

  /// Le nom d'un mois, de 1 à 12, en minuscules.
  ///
  /// LES MOIS SONT CEUX DE L'ALGÉRIE, et c'est un choix. L'arabe standard
  /// connaît deux séries de noms : celle du Machrek — يناير, فبراير — et celle
  /// du Maghreb, empruntée au français : جانفي, فيفري, أفريل, جوان, جويلية,
  /// أوت. C'est la seconde qu'on lit sur un calendrier algérien, dans un journal
  /// algérien et sur un acte d'état civil algérien. La première serait de
  /// l'arabe correct écrit pour quelqu'un d'autre.
  String mois(int numero) => switch (numero) {
    1 => _textes.moisJanvier,
    2 => _textes.moisFevrier,
    3 => _textes.moisMars,
    4 => _textes.moisAvril,
    5 => _textes.moisMai,
    6 => _textes.moisJuin,
    7 => _textes.moisJuillet,
    8 => _textes.moisAout,
    9 => _textes.moisSeptembre,
    10 => _textes.moisOctobre,
    11 => _textes.moisNovembre,
    _ => _textes.moisDecembre,
  };

  /// Le mois avec sa capitale initiale — « Août », pour un titre.
  ///
  /// L'ARABE N'A PAS DE CAPITALES, et `toUpperCase()` y est sans effet : la
  /// méthode rend alors le mois inchangé, ce qui est exactement ce qu'il faut.
  /// On ne teste donc pas la langue ici — l'écriture s'en charge d'elle-même.
  String moisEnTitre(int numero) {
    final nom = mois(numero);
    if (nom.isEmpty) return nom;
    return nom[0].toUpperCase() + nom.substring(1);
  }

  /// Le nom d'un jour de la semaine, dans l'ordre de `DateTime.weekday`.
  String jour(DateTime date) => switch (date.weekday) {
    DateTime.monday => _textes.jourLundi,
    DateTime.tuesday => _textes.jourMardi,
    DateTime.wednesday => _textes.jourMercredi,
    DateTime.thursday => _textes.jourJeudi,
    DateTime.friday => _textes.jourVendredi,
    DateTime.saturday => _textes.jourSamedi,
    _ => _textes.jourDimanche,
  };

  /// « 14 août 2027 ».
  String date(DateTime jour) =>
      _textes.dateEnClair('${jour.day}', mois(jour.month), '${jour.year}');

  /// « 14 août », sans l'année — pour les puces, où la place manque.
  String dateCourte(DateTime jour) =>
      _textes.dateCourte('${jour.day}', mois(jour.month));

  /// « samedi 14 août 2027 ».
  String jourEtDate(DateTime date) =>
      _textes.jourEtDate(jour(date), this.date(date));

  /// « Août 2027 » — le titre d'un mois de calendrier.
  String moisEtAnnee(DateTime mois) =>
      _textes.moisEtAnnee(moisEnTitre(mois.month), '${mois.year}');

  /// Les sept initiales de l'en-tête du calendrier, DIMANCHE EN TÊTE.
  ///
  /// L'ORDRE NE CHANGE PAS EN ARABE, et c'est le troisième piège du §10 : « le
  /// calendrier commence toujours par dimanche, mais se lit de droite à
  /// gauche ». Le miroir est affaire de direction du texte — le `Row` de la
  /// grille suit la `Directionality` et pose sa première colonne à droite — et
  /// non d'ordre des colonnes. Inverser cette liste en arabe mettrait samedi en
  /// tête, c'est-à-dire décalerait toutes les dates d'un cran.
  List<String> get initialesDesJours => <String>[
    _textes.initialeDimanche,
    _textes.initialeLundi,
    _textes.initialeMardi,
    _textes.initialeMercredi,
    _textes.initialeJeudi,
    _textes.initialeVendredi,
    _textes.initialeSamedi,
  ];
}

/// L'espacement des capitales d'un intitulé de section.
///
/// Voir l'en-tête : la charte espace les capitales latines, et l'arabe ne le
/// supporte pas — ses lettres se lient.
extension EspacementDesCapitales on BuildContext {
  /// L'espacement à poser sur un intitulé en capitales.
  ///
  /// [enLatin] est la valeur de la charte pour cet intitulé-là — 1,2 pour les
  /// titres de section, 1 pour les trois chiffres de la fiche. En arabe, la
  /// réponse est toujours zéro.
  double espacementDesCapitales([double enLatin = 1.2]) =>
      Directionality.of(this) == TextDirection.rtl ? 0 : enLatin;
}
