/// La grille d'un mois : sept colonnes, dimanche en tête, des cases carrées.
///
/// EXTRAITE DE L'ÉCRAN 4, PAS RÉÉCRITE. Le calendrier client (§4.2, CLI-04) et
/// l'agenda du propriétaire (§4.3, OWN-06) dessinent la même chose et n'y
/// mettent pas la même information : l'un des cercles de disponibilité, l'autre
/// cinq états et deux créneaux. Ce fichier ne connaît que la GÉOMÉTRIE — combien
/// de colonnes, où commence le mois, quelle taille fait une case — et laisse
/// tout le reste à celui qui l'appelle, par [MoisCalendrier.caseDuJour].
///
/// PAS DE GridView, ET C'EST LE POINT DE L'EXTRACTION. On a déjà payé ce
/// bug-là : un `GridView` imbriqué dans une liste défilante veut une hauteur
/// qu'il n'a pas, et il faut alors le brider avec `shrinkWrap` et
/// `NeverScrollableScrollPhysics` — deux réglages qui reconstruisent tout à
/// chaque image. Des `Row` d'`Expanded` autour d'`AspectRatio` donnent la même
/// grille sans rien de tout cela, et se composent avec n'importe quel parent.
/// Le second écran reprend donc celle qui marche au lieu d'en refaire une.
library;

import 'package:flutter/material.dart';

import '../l10n/formats_ferha.dart';
import '../theme/ferha_colors.dart';

/// Un mois entier : son titre, la ligne des initiales, et la grille.
class MoisCalendrier extends StatelessWidget {
  /// Crée la grille d'un mois.
  const MoisCalendrier({
    required this.mois,
    required this.caseDuJour,
    this.avecTitre = true,
    super.key,
  });

  /// N'importe quel jour du mois voulu : seuls l'année et le mois comptent.
  final DateTime mois;

  /// Ce qu'on pose dans la case d'un jour.
  ///
  /// C'est là que passe tout ce que cette grille ignore : les couleurs, les
  /// gestes, ce qui est barré et ce qui ne l'est pas. La case reçoit un carré,
  /// et en fait ce qu'elle veut.
  final Widget Function(DateTime jour) caseDuJour;

  /// « Août 2027 » au-dessus de la grille.
  ///
  /// Vrai pour le calendrier client, qui empile dix-huit mois à la file et où
  /// chacun doit se nommer. Faux pour l'agenda, qui n'en montre qu'un et le
  /// nomme dans sa barre de navigation — l'écrire deux fois ferait lire deux
  /// fois la même chose.
  final bool avecTitre;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final formats = FormatsFerha.de(context);

    final nombreDeJours = DateTime(mois.year, mois.month + 1, 0).day;
    final decalage = colonneDuJour(DateTime(mois.year, mois.month));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (avecTitre) ...<Widget>[
          Text(
            formats.moisEtAnnee(mois),
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
        ],
        // DIMANCHE EN TÊTE, ET IL Y RESTE EN ARABE.
        //
        // C'est la charte qui tranche, et deux fois plutôt qu'une : les
        // maquettes de l'écran 4 affichent « D L M M J V S », et le paragraphe
        // sur le miroir RTL précise que « le calendrier commence toujours par
        // dimanche mais se lit de droite à gauche ». Le miroir est donc affaire
        // de DIRECTION — ce `Row` suit la `Directionality` et pose sa première
        // colonne à droite en arabe — et non d'ordre : inverser cette liste
        // mettrait samedi en tête et décalerait toutes les dates d'un cran.
        Row(
          children: <Widget>[
            for (final j in formats.initialesDesJours)
              Expanded(
                child: Center(
                  child: Text(
                    j,
                    style: text.labelSmall?.copyWith(color: colors.inkTertiary),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        SemainesCalendrier(
          cases: <Widget>[
            // Les cases vides du début, jusqu'au premier jour du mois.
            for (var i = 0; i < decalage; i++) const SizedBox.shrink(),
            for (var jourDuMois = 1; jourDuMois <= nombreDeJours; jourDuMois++)
              caseDuJour(DateTime(mois.year, mois.month, jourDuMois)),
          ],
        ),
      ],
    );
  }
}

/// Sept colonnes, autant de rangées qu'il faut, et AUCUN défilement.
///
/// SURTOUT PAS UN GridView. Imbriqué dans le ListView des mois, même en
/// `NeverScrollableScrollPhysics`, un GridView reste un `Scrollable` : il
/// s'inscrit auprès du système de pointeurs et capte la molette au lieu de la
/// laisser remonter au parent. Le calendrier s'accroche alors sous le curseur,
/// et le défilement ne repart qu'en sortant de la grille — c'est-à-dire
/// presque nulle part, puisque la grille occupe l'écran.
///
/// Sept cases par rangée se posent très bien à la main, et une rangée n'est
/// pas un `Scrollable`.
class SemainesCalendrier extends StatelessWidget {
  /// Crée la grille.
  const SemainesCalendrier({required this.cases, super.key});

  /// Les cases, dans l'ordre, la première rangée d'abord.
  final List<Widget> cases;

  /// L'écart entre deux cases.
  ///
  /// Les cercles occupent toute leur case : c'est donc cet écart, et lui seul,
  /// qui les empêche de se toucher. À 4 ils se frôlaient.
  static const double _ecart = 8;

  @override
  Widget build(BuildContext context) {
    final rangees = <Widget>[];

    for (var debut = 0; debut < cases.length; debut += 7) {
      final fin = debut + 7 <= cases.length ? debut + 7 : cases.length;
      final semaine = cases.sublist(debut, fin);

      rangees.add(
        Row(
          spacing: _ecart,
          children: <Widget>[
            for (final c in semaine)
              Expanded(child: AspectRatio(aspectRatio: 1, child: c)),
            // La dernière rangée est rarement pleine : on la complète pour que
            // ses cases gardent la largeur de celles du dessus.
            for (var i = semaine.length; i < 7; i++)
              const Expanded(child: SizedBox.shrink()),
          ],
        ),
      );
    }

    return Column(spacing: _ecart, children: rangees);
  }
}

/// La colonne d'un jour dans la grille, dimanche en tête.
///
/// `DateTime.weekday` vaut 1 pour lundi et 7 pour dimanche. Le reste modulo 7
/// donne donc directement la colonne d'une semaine qui commence par dimanche :
/// dimanche 0, lundi 1, samedi 6.
///
/// Ne pas lire les DATES de la maquette : ses cases portent des « contenus
/// fictifs », elle y place le 14 août 2027 un jeudi quand c'est un samedi —
/// que sa propre légende nomme d'ailleurs correctement. Elle donne la
/// structure, pas le calendrier.
int colonneDuJour(DateTime jour) => jour.weekday % 7;

/// Vrai quand deux dates tombent le même jour, l'heure ignorée.
bool memeJour(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// LE NOM FRANÇAIS D'UN MOIS N'EST PLUS ICI.
//
// Cette grille est partagée par le calendrier client, traduit au J22, et par
// l'agenda du propriétaire, qui ne l'est pas. Son titre passe désormais par
// `FormatsFerha.moisEtAnnee()` et suit donc la langue de l'application.
//
// `nomMois` a suivi son dernier lecteur, dans `agenda_screen.dart` : un fichier
// partagé qui garderait douze mots français serait le premier endroit où l'on
// oublierait de traduire.
