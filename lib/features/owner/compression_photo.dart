import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'photo_de_salle.dart';

/// La compression avant envoi (§7.3), et le choix des photos.
///
/// POURQUOI COMPRESSER, ET LA PHRASE EST DANS LE CAHIER DES CHARGES : « sur une
/// 4G algérienne, envoyer 12 photos brutes de 4 Mo fait abandonner le
/// propriétaire au milieu du formulaire ». Une photo de téléphone fait 3 à 5 Mo
/// et 4000 px de large ; réduite à 1600 px et réencodée à 80 %, elle en fait
/// 200 à 400 Ko. C'est dix fois moins à faire passer, et c'est la différence
/// entre six photos en quinze secondes et six photos qu'on n'enverra pas.
///
/// DEUX INTERFACES PLUTÔT QUE DEUX APPELS DIRECTS, et pour la même raison que
/// [OwnerRepository] : les tests les remplacent en bloc. Un écran monté sur une
/// fausse compression et un faux sélecteur n'a besoin ni d'appareil photo, ni
/// d'encodeur natif, ni de canevas — et `flutter test` n'en a aucun.

// =============================================================================
// Les deux consignes du §7.3
// =============================================================================

/// La largeur maximale d'une photo envoyée, en pixels.
const int largeurMaximale = 1600;

/// La qualité d'encodage, sur cent.
const int qualiteEncodage = 80;

// =============================================================================
// Choisir des photos
// =============================================================================

/// D'où viennent les photos : l'appareil, ou la galerie (écran 10).
abstract interface class SelecteurDePhotos {
  /// Prend une photo avec l'appareil. Rend `null` si l'on renonce.
  Future<XFile?> appareilPhoto();

  /// Choisit plusieurs photos dans la galerie, [maximum] au plus.
  ///
  /// Rend une liste vide si l'on renonce.
  Future<List<XFile>> galerie({required int maximum});
}

/// Le vrai sélecteur, celui d'`image_picker`.
class SelecteurImagePicker implements SelecteurDePhotos {
  /// Crée le sélecteur.
  SelecteurImagePicker([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// ON NE PASSE NI `maxWidth` NI `imageQuality` À `image_picker`, ALORS QU'IL
  /// SAIT LES DEUX. Sa réduction à lui rend du JPEG, toujours — et le §7.3
  /// demande du WebP. On récupère donc l'original et c'est [CompresseurDePhoto]
  /// qui réduit, une bonne fois, dans le format voulu. Réduire deux fois
  /// coûterait de la netteté pour rien.
  @override
  Future<XFile?> appareilPhoto() =>
      _picker.pickImage(source: ImageSource.camera);

  @override
  Future<List<XFile>> galerie({required int maximum}) =>
      _picker.pickMultiImage(limit: maximum);
}

/// Le sélecteur de l'application.
final selecteurDePhotosProvider = Provider<SelecteurDePhotos>(
  (ref) => SelecteurImagePicker(),
);

// =============================================================================
// Compresser
// =============================================================================

/// Réduit une photo et la réencode (§7.3).
abstract interface class CompresseurDePhoto {
  /// Rend les octets réduits, et le format qu'ils ont VRAIMENT.
  ///
  /// Lève [EchecDeCompression] quand rien d'acceptable n'a pu être produit.
  Future<PhotoCompressee> compresser(Uint8List origine);
}

/// Ce qui est levé quand aucun format acceptable n'est sorti de l'encodeur.
class EchecDeCompression implements Exception {
  /// Crée l'échec.
  const EchecDeCompression(this.message);

  /// Ce qui s'est passé, en français, prêt à s'afficher.
  final String message;

  @override
  String toString() => 'EchecDeCompression: $message';
}

/// Le vrai compresseur : l'encodeur du système sur Android, celui du navigateur
/// sur le web.
///
/// LE PIÈGE DE CE FICHIER, ET LA RAISON POUR LAQUELLE IL RENIFLE LES OCTETS.
/// Sur le web, `flutter_image_compress` finit par appeler
/// `canvas.toDataURL('image/webp', 0.8)`. Or `toDataURL` ne refuse jamais un
/// format qu'il ne connaît pas : il retombe SILENCIEUSEMENT sur du PNG, et rend
/// une chaîne qui commence par `data:image/png;base64,`. Le paquet, lui, jette
/// ce préfixe et ne rend que les octets — son API ne peut donc pas dire quel
/// format est vraiment sorti. Un appelant qui ferait confiance à ce qu'il a
/// demandé écrirait « photo.webp » sur un PNG, l'enverrait avec
/// `Content-Type: image/webp`, et le bucket (021, `allowed_mime_types`) le
/// refuserait — sans que personne comprenne pourquoi.
///
/// On lit donc les premiers octets, qui eux ne mentent pas. Et si ce n'est ni du
/// WebP ni du JPEG, on redemande explicitement du JPEG, qui est le repli du
/// §7.3. Sur Android, le premier essai rend toujours du WebP —
/// `Bitmap.compress(WEBP)` est dans le système depuis toujours ; le reniflement
/// n'y coûte que la lecture de douze octets, et il vaut mieux le même code des
/// deux côtés qu'un `kIsWeb` de plus.
class CompresseurNatif implements CompresseurDePhoto {
  /// Crée le compresseur.
  const CompresseurNatif();

  @override
  Future<PhotoCompressee> compresser(Uint8List origine) async {
    final essai = await _encoder(origine, CompressFormat.webp);
    final formatObtenu = reconnaitreFormat(essai);

    // Le cas normal des deux côtés : on a demandé du WebP et on en a reçu. Le
    // JPEG est accepté ici aussi — si un encodeur décidait d'en rendre, il n'y
    // aurait aucune raison de le réencoder une seconde fois.
    if (formatObtenu != null) {
      return PhotoCompressee(octets: essai, format: formatObtenu);
    }

    // Le navigateur a rendu autre chose — du PNG, en pratique. On redemande
    // donc le repli, en le nommant cette fois.
    final repli = await _encoder(origine, CompressFormat.jpeg);
    final formatRepli = reconnaitreFormat(repli);

    if (formatRepli == null) {
      throw const EchecDeCompression(
        'Cette image n’a pas pu être préparée pour l’envoi. Essayez une autre '
        'photo, ou un autre navigateur.',
      );
    }

    return PhotoCompressee(octets: repli, format: formatRepli);
  }

  /// `minHeight: 1` N'EST PAS UNE ÉTOURDERIE, C'EST LA CONSIGNE DU §7.3.
  ///
  /// Les deux implémentations calculent la même échelle :
  /// `max(1, min(largeur / minWidth, hauteur / minHeight))`. Avec un
  /// `minHeight` réaliste, une photo en portrait serait réduite d'après sa
  /// HAUTEUR et resterait plus large que 1600. Avec `minHeight: 1`, le second
  /// rapport est toujours énorme, l'échelle vient donc toujours de la largeur,
  /// et la règle devient exactement celle qu'on voulait : « largeur maximale
  /// 1600 px ». Le `max(1, …)` de leur côté garantit qu'une petite photo n'est
  /// jamais AGRANDIE.
  Future<Uint8List> _encoder(Uint8List origine, CompressFormat format) =>
      FlutterImageCompress.compressWithList(
        origine,
        minWidth: largeurMaximale,
        minHeight: 1,
        quality: qualiteEncodage,
        format: format,
      );
}

/// Le compresseur de l'application.
final compresseurDePhotoProvider = Provider<CompresseurDePhoto>(
  (ref) => const CompresseurNatif(),
);

/// Ce que des octets d'image SONT, lu dans leur en-tête.
///
/// Rend `null` pour tout ce qui n'est ni du WebP ni du JPEG — PNG compris, et
/// c'est le cas qui compte (voir [CompresseurNatif]).
///
/// Les deux signatures sont celles des spécifications, et rien d'autre :
///
///   * WebP  : « RIFF » sur quatre octets, quatre octets de taille, « WEBP » ;
///   * JPEG  : FF D8 FF, le marqueur de début d'image.
///
/// Publique, et non privée, parce que c'est elle que le test épingle : la règle
/// « jamais un PNG déguisé en .webp » se vérifie ici, sans appareil ni
/// navigateur.
FormatPhoto? reconnaitreFormat(Uint8List octets) {
  if (octets.length >= 12 &&
      octets[0] == 0x52 && // R
      octets[1] == 0x49 && // I
      octets[2] == 0x46 && // F
      octets[3] == 0x46 && // F
      octets[8] == 0x57 && // W
      octets[9] == 0x45 && // E
      octets[10] == 0x42 && // B
      octets[11] == 0x50) {
    // P
    return FormatPhoto.webp;
  }

  if (octets.length >= 3 &&
      octets[0] == 0xFF &&
      octets[1] == 0xD8 &&
      octets[2] == 0xFF) {
    return FormatPhoto.jpeg;
  }

  return null;
}
