/// Le sens d'écriture d'un texte, déduit du texte lui-même.
///
/// POURQUOI PAS LA LANGUE DE L'APPLICATION. Deux textes de ce projet ne
/// choisissent pas leur langue : la réponse de l'assistant, qui répond dans la
/// langue de la QUESTION, et la synthèse des avis, rédigée dans la langue des
/// avis qu'elle résume. Une personne qui a mis l'application en français peut
/// très bien écrire en darja, et lire alors une réponse en arabe ; la poser à
/// gauche, ponctuation comprise, la rendrait illisible.
///
/// La barre d'onglets, les boutons et les titres, eux, suivent la langue de
/// l'application comme partout ailleurs : ce fichier ne concerne QUE le texte
/// dont la langue vient d'ailleurs.
///
/// =============================================================================
/// COMMENT ON TRANCHE : LE PREMIER CARACTÈRE FORT
///
/// C'est l'algorithme bidirectionnel d'Unicode, réduit à ce qu'il nous faut : on
/// parcourt le texte jusqu'au premier caractère qui porte un sens — une lettre —
/// et c'est lui qui décide. Les chiffres, la ponctuation et les espaces n'en
/// portent aucun : « 300 invités » et « 300 مدعو » commencent tous deux par un
/// chiffre, et seul le mot qui suit les sépare.
///
/// Une réponse en arabe qui cite « Salle Ibn Khaldoun » en écriture latine reste
/// donc une réponse arabe : ces quelques lettres latines sont au milieu, pas au
/// début, et Flutter les rend correctement dans un paragraphe RTL.
library;

import 'package:flutter/widgets.dart';

/// Les deux plages qui décident : l'arabe, et ses formes de présentation.
///
/// U+0600–U+06FF est l'arabe courant ; U+0750–U+077F ses suppléments ;
/// U+FB50–U+FDFF et U+FE70–U+FEFF les formes de présentation, qu'un copier-coller
/// ramène parfois d'un document ancien.
///
/// L'HÉBREU N'Y EST PAS, et ce n'est pas un oubli : Ferha est bilingue français /
/// arabe (§10), et une plage de plus serait du code qu'aucun écran n'exercerait.
bool _estArabe(int c) =>
    (c >= 0x0600 && c <= 0x06FF) ||
    (c >= 0x0750 && c <= 0x077F) ||
    (c >= 0xFB50 && c <= 0xFDFF) ||
    (c >= 0xFE70 && c <= 0xFEFF);

/// Vrai pour une lettre latine — le second caractère « fort » qui nous intéresse.
bool _estLatin(int c) =>
    (c >= 0x0041 && c <= 0x005A) ||
    (c >= 0x0061 && c <= 0x007A) ||
    (c >= 0x00C0 && c <= 0x024F);

/// Le sens d'écriture de [texte].
///
/// Rend [TextDirection.ltr] quand le texte est vide ou ne porte aucune lettre :
/// « 250 000 » n'a pas de sens d'écriture propre, et la valeur par défaut de
/// l'application est le français.
TextDirection directionDuTexte(String texte) {
  for (final rune in texte.runes) {
    if (_estArabe(rune)) return TextDirection.rtl;
    if (_estLatin(rune)) return TextDirection.ltr;
  }
  return TextDirection.ltr;
}

/// [texte] enveloppé dans sa propre direction.
///
/// À POSER AUTOUR DU TEXTE, ET NON AUTOUR DE LA BULLE. La bulle appartient à
/// l'écran, donc à la langue de l'application : c'est elle qui décide si la
/// réponse est alignée au début ou à la fin de la ligne. Le paragraphe, lui,
/// appartient à sa propre langue. Envelopper la bulle entière ferait sauter les
/// réponses d'un bord à l'autre de l'écran au gré de la langue de chacune.
class TexteDansSaLangue extends StatelessWidget {
  /// Crée un texte affiché dans le sens de sa propre langue.
  const TexteDansSaLangue(this.texte, {this.style, super.key});

  /// Le texte, dont la langue n'est pas celle de l'application.
  final String texte;

  /// Le style, comme pour un [Text] ordinaire.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final direction = directionDuTexte(texte);

    return Directionality(
      textDirection: direction,
      child: Text(texte, style: style, textAlign: TextAlign.start),
    );
  }
}
