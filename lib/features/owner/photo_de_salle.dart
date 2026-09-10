import 'dart:math';

import 'package:flutter/foundation.dart';

/// Une photo déjà enregistrée dans la galerie d'une salle (§4.3, OWN-02).
///
/// C'est une ligne de `venue_photos`, telle que la rendent `ajouter_photo()`,
/// `reordonner_photos()` et la lecture directe de la table.
///
/// [estCouverture] N'EST PAS UNE SECONDE VÉRITÉ. La migration 021 pose
/// `check (is_cover = (position = 0))` : le champ ne peut PAS dire autre chose
/// que le rang, en base. On le garde quand même ici plutôt que de le recalculer,
/// parce qu'un écran qui affiche « Couverture » doit afficher ce que la base
/// dit, pas ce qu'on en déduit — le jour où les deux divergeraient, on veut le
/// voir, pas le masquer.
@immutable
class PhotoDeSalle {
  /// Crée une photo.
  const PhotoDeSalle({
    required this.id,
    required this.chemin,
    required this.position,
    required this.estCouverture,
  });

  /// Construit depuis une ligne de `venue_photos`.
  factory PhotoDeSalle.depuisJson(Map<String, dynamic> j) => PhotoDeSalle(
    id: j['id'] as String,
    chemin: j['storage_path'] as String,
    position: (j['position'] as num).toInt(),
    estCouverture: j['is_cover'] as bool,
  );

  /// L'identifiant de la ligne.
  final String id;

  /// Le chemin dans le bucket : `{venue_id}/{uuid}.webp`.
  ///
  /// Un chemin, pas une URL — c'est la règle du dépôt, et `urlPhoto()`
  /// (lib/core/widgets/photo_salle.dart) est le seul endroit qui la résout.
  final String chemin;

  /// Le rang d'affichage, à partir de zéro.
  final int position;

  /// Vrai pour la photo de couverture, donc pour celle de rang zéro.
  final bool estCouverture;
}

/// Le format qu'une photo compressée a VRAIMENT.
///
/// DEUX VALEURS, ET PAS DE PNG. Le §7.3 demande du WebP ; le JPEG est le repli
/// assumé des navigateurs qui ne savent pas l'encoder. Le PNG, lui, n'est pas un
/// repli : une photo en PNG pèse cinq fois le JPEG équivalent, et c'est
/// exactement ce qu'on cherche à éviter sur une 4G algérienne. Il n'a donc pas
/// de valeur ici — quand il sort d'un encodeur, c'est un échec, pas un choix.
enum FormatPhoto {
  /// Ce qu'on demande, et ce qu'on obtient partout sauf sur de vieux Safari.
  webp('image/webp', '.webp'),

  /// Le repli, quand le navigateur ne sait pas encoder du WebP.
  jpeg('image/jpeg', '.jpg');

  const FormatPhoto(this.typeMime, this.extension);

  /// Le `Content-Type` envoyé au Storage. Il doit être dans
  /// `allowed_mime_types` du bucket (021), sans quoi le fichier est refusé.
  final String typeMime;

  /// L'extension du fichier, point compris.
  ///
  /// ELLE SUIT LE FORMAT RÉEL, JAMAIS CELUI QU'ON AVAIT DEMANDÉ. Nommer
  /// « .webp » un fichier JPEG ne casserait rien tout de suite — les
  /// navigateurs lisent l'en-tête, pas le nom — mais mentirait à tout ce qui
  /// vient après : un tri, un nettoyage, un humain qui regarde le bucket.
  final String extension;
}

/// Ce qui sort de la compression : des octets, et ce qu'ils sont vraiment.
///
/// LES DEUX VONT ENSEMBLE, ET C'EST TOUT L'INTÉRÊT DE CETTE CLASSE. Rendre un
/// `Uint8List` seul laisserait l'appelant supposer le format — et il supposerait
/// celui qu'il a demandé, qui n'est pas toujours celui qu'il a reçu. Ici, le
/// format vient d'une lecture des octets, et il voyage avec eux jusqu'au nom du
/// fichier et à l'en-tête `Content-Type`.
@immutable
class PhotoCompressee {
  /// Crée une photo compressée.
  const PhotoCompressee({required this.octets, required this.format});

  /// Les octets à envoyer.
  final Uint8List octets;

  /// Ce que ces octets sont — reconnu, pas supposé.
  final FormatPhoto format;

  /// Le poids en kilo-octets, pour l'afficher.
  int get kilooctets => (octets.lengthInBytes / 1024).round();
}

/// Le chemin de Storage d'une nouvelle photo : `{venue_id}/{uuid}.webp`.
///
/// C'est le §7.3 mot pour mot, et c'est aussi ce que `venue_du_chemin()` (021)
/// sait relire : le premier segment est l'identifiant de la salle, et c'est de
/// lui que dépendent les trois politiques du bucket.
String cheminDePhoto(String venueId, FormatPhoto format) =>
    '$venueId/${_uuidV4()}${format.extension}';

/// Un UUID version 4, sans dépendance.
///
/// PAS DE PAQUET POUR SEIZE OCTETS AU HASARD. `uuid` ferait très bien l'affaire,
/// mais ce serait une dépendance de plus à suivre pour ce que `Random.secure()`
/// donne en dix lignes. Les deux marqueurs de la version 4 sont posés comme la
/// RFC 4122 les demande : le quatrième quartet vaut 4, et le premier du
/// neuvième octet vaut 8, 9, a ou b.
String _uuidV4() {
  final hasard = Random.secure();
  final octets = List<int>.generate(16, (_) => hasard.nextInt(256));

  octets[6] = (octets[6] & 0x0f) | 0x40;
  octets[8] = (octets[8] & 0x3f) | 0x80;

  final hexa = octets.map((o) => o.toRadixString(16).padLeft(2, '0')).join();

  return '${hexa.substring(0, 8)}-${hexa.substring(8, 12)}-'
      '${hexa.substring(12, 16)}-${hexa.substring(16, 20)}-'
      '${hexa.substring(20)}';
}
