import 'dart:async';

import 'package:flutter/material.dart';

/// Le temps qui reste, en toutes lettres, et qui descend tout seul.
///
/// « 71 h 12 min », comme l'écran 6 des maquettes — et la remarque qui
/// l'accompagne dit pourquoi : « Le compte à rebours de 72 h est affiché en
/// toutes lettres. » Pas « 71:12:04 », qui se lit comme une heure ; pas une
/// barre de progression, qui ne dit pas combien il reste.
///
/// IL BAT À LA SECONDE, MAIS NE SE REDESSINE QU'À LA MINUTE. La minuterie
/// tourne toutes les secondes pour que le passage d'une minute à la suivante se
/// voie à l'instant où il arrive ; mais on ne rebâtit le widget que si le TEXTE
/// a changé. Soixante reconstructions par minute pour afficher le même mot
/// seraient soixante de trop, et un compte à rebours qui saute d'une minute
/// avec trente secondes de retard donne l'impression d'une application arrêtée.
class CompteARebours extends StatefulWidget {
  /// Crée un compte à rebours jusqu'à [echeance].
  const CompteARebours({
    required this.echeance,
    required this.style,
    this.quandEcoule = 'délai écoulé',
    this.maintenant = DateTime.now,
    super.key,
  });

  /// L'instant où le délai expire, en heure locale.
  final DateTime echeance;

  /// Le style du texte.
  final TextStyle? style;

  /// L'heure qu'il est.
  ///
  /// `DateTime.now` partout, sauf en test. Un test de widget avance une horloge
  /// FEINTE — celle des minuteries et des animations — mais `DateTime.now()`,
  /// lui, continue de lire la vraie : sans cette couture, on ne pourrait
  /// vérifier que la minuterie se déclenche, jamais que le texte change. Or
  /// c'est le texte qui compte : c'est lui qui doit descendre tout seul.
  final DateTime Function() maintenant;

  /// Ce qu'on écrit une fois l'échéance passée.
  ///
  /// L'écran ne se met pas à jour tout seul côté base à cet instant : c'est le
  /// cron `expire_options()` (§7.2) qui fera passer la réservation à
  /// « expirée », et il tourne à l'heure. Entre les deux, dire « délai écoulé »
  /// est plus honnête que d'afficher « 0 h 00 min » ou de laisser le compteur
  /// passer en négatif.
  final String quandEcoule;

  @override
  State<CompteARebours> createState() => _CompteAReboursState();
}

class _CompteAReboursState extends State<CompteARebours> {
  late String _texte = _calcule();
  Timer? _minuterie;

  @override
  void initState() {
    super.initState();
    _minuterie = Timer.periodic(const Duration(seconds: 1), (_) => _bat());
  }

  @override
  void didUpdateWidget(CompteARebours ancien) {
    super.didUpdateWidget(ancien);
    // L'échéance a changé — une autre réservation a pris la place de
    // celle-ci dans la liste. On repart du bon compte, sans attendre une
    // seconde de plus.
    if (widget.echeance != ancien.echeance) _texte = _calcule();
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    super.dispose();
  }

  void _bat() {
    final nouveau = _calcule();
    if (nouveau != _texte) setState(() => _texte = nouveau);
  }

  String _calcule() => resteEnFrancais(
    widget.echeance.difference(widget.maintenant()),
    quandEcoule: widget.quandEcoule,
  );

  @override
  Widget build(BuildContext context) => Text(_texte, style: widget.style);
}

/// « 71 h 12 min », « 12 min », « moins d'une minute ».
///
/// Les heures ne se convertissent pas en jours : « 2 j 23 h » demande un calcul
/// mental pour savoir si l'on tient jusqu'à demain soir, là où « 71 h » se
/// compare directement aux 72 h annoncées. C'est le choix de la maquette, et il
/// est juste.
@visibleForTesting
String resteEnFrancais(Duration reste, {String quandEcoule = 'délai écoulé'}) {
  if (reste.isNegative || reste == Duration.zero) return quandEcoule;

  final heures = reste.inHours;
  final minutes = reste.inMinutes % 60;

  if (heures > 0) {
    // Deux chiffres aux minutes quand elles suivent des heures : « 71 h 07 min »
    // s'aligne d'une ligne à l'autre, « 71 h 7 min » danse.
    return '$heures h ${minutes.toString().padLeft(2, '0')} min';
  }
  if (minutes > 0) return '$minutes min';

  return 'moins d’une minute';
}
