/// La règle du numéro de téléphone, côté Flutter.
///
/// ELLE EST ÉCRITE DEUX FOIS, ET DEUX FOIS SEULEMENT : ici, et en SQL dans
/// `telephone_valide()` (migration 020). Les deux exemplaires ne sont pas une
/// duplication qu'on aurait laissée passer — ils répondent à deux questions
/// différentes, au même endroit du parcours :
///
///   * celui-ci ÉTEINT LE BOUTON avant qu'on appuie, et dit la forme attendue ;
///   * celui de la base REFUSE, et c'est lui le dernier mot — un client modifié
///     ne le contourne pas.
///
/// Sans le premier, on tape son numéro, on appuie, on attend le réseau, et on
/// apprend qu'il manquait un chiffre. Sans le second, il suffirait d'un client
/// bricolé pour poser n'importe quoi dans `profiles.phone`.
///
/// C'est `supabase/tests/007_adresse_et_telephone.sql` qui empêche les deux de
/// diverger : il compare la règle SQL aux mêmes numéros que
/// `test/telephone_test.dart`. Le jour où l'Algérie ouvre un préfixe, il y a
/// exactement deux endroits à ouvrir, et un test de chaque côté pour le dire.
///
/// LA RÈGLE
///
///   * mobile : 0, puis 5, 6 ou 7, puis 8 chiffres — 0770112233 (10 chiffres)
///   * fixe   : 0, puis 2, 3 ou 4, puis 7 chiffres — 041234567  (9 chiffres)
///   * les espaces sont tolérés à la saisie ; la base ne garde que les chiffres.
library;

/// Le numéro de téléphone algérien : sa forme, et ce qu'on en garde.
abstract final class TelephoneAlgerien {
  /// Ce que la base gardera : le numéro sans ses espaces.
  ///
  /// SEULS LES BLANCS SONT RETIRÉS, comme en SQL. Ni les points, ni les tirets,
  /// ni un « +213 » : ceux-là ne sont pas de la mise en forme, ce sont d'autres
  /// façons d'écrire le numéro, et les rattraper en silence reviendrait à
  /// deviner. On préfère le dire.
  static String normalise(String saisie) =>
      saisie.replaceAll(RegExp(r'\s'), '');

  /// Vrai quand le numéro suit la règle.
  ///
  /// Un numéro absent n'est pas un numéro invalide, mais il n'est pas valide
  /// non plus : c'est à l'écran de dire si l'absence est permise — et sur les
  /// deux écrans qui appellent cette méthode, elle ne l'est pas.
  static bool estValide(String? saisie) =>
      saisie != null && _forme.hasMatch(normalise(saisie));

  /// Ce qui manque au numéro pour être envoyable, ou `null` s'il va bien.
  ///
  /// LA PHRASE EST LE POINT DE CETTE MÉTHODE, pas le booléen — c'est la même
  /// idée que `NouvelleSalle.ceQuiManque`. Deux phrases, parce qu'il y a deux
  /// situations : un champ vide n'est pas une faute, un numéro à moitié tapé
  /// en est presque une. On ne gronde pas le premier, et on donne un exemple
  /// au second plutôt qu'une règle à déchiffrer.
  static String? ceQuiManque(String saisie) {
    if (normalise(saisie).isEmpty) return 'Indiquez un numéro de téléphone.';
    if (!estValide(saisie)) {
      return 'Ce numéro n’a pas la bonne forme. Exemples : 0770 11 22 33, '
          'ou 041 23 45 67 pour un fixe.';
    }
    return null;
  }

  /// Mobile — 0, puis 5, 6 ou 7, puis huit chiffres — ou fixe — 0, puis 2, 3
  /// ou 4, puis sept chiffres.
  ///
  /// LE DEUXIÈME CHIFFRE FAIT TOUT LE TRAVAIL, et c'est pour lui que la règle
  /// distingue deux formes plutôt que d'accepter « 0 et huit chiffres ». Cette
  /// version-là laissait passer « 077011223 » — un mobile auquel il manque un
  /// chiffre, qui a exactement la longueur d'un fixe. Il serait entré en base
  /// sans que rien ne bronche, et le propriétaire l'aurait découvert le jour où
  /// personne ne l'aurait rappelé.
  ///
  /// ON NE VA PAS PLUS LOIN : pas de liste des indicatifs de wilaya. « 049 »
  /// n'est attribué à personne, et cette règle l'accepte — la refuser
  /// demanderait de tenir les 58 indicatifs à jour ici ET en SQL, pour attraper
  /// une faute de frappe que le propriétaire verra lui-même. On borne la FORME,
  /// pas l'annuaire.
  static final RegExp _forme = RegExp(r'^(0[567][0-9]{8}|0[234][0-9]{7})$');
}
