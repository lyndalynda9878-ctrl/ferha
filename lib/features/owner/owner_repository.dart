import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/preferences/preferences_affichage.dart';
import '../../core/supabase/supabase_providers.dart';
import '../search/search_filters.dart';
import 'creneau_agenda.dart';
import 'demande_detail.dart';
import 'demande_en_attente.dart';
import 'indicateurs_salle.dart';
import 'nouvelle_salle.dart';
import 'photo_de_salle.dart';
import 'salle_du_proprietaire.dart';

/// Les trois lectures de l'espace propriétaire (§4.3 ; écran 9).
///
/// UNE INTERFACE PLUTÔT QUE TROIS FONCTIONS LIBRES, pour une seule raison : les
/// tests la remplacent en bloc, comme ils remplacent [PreferencesAffichage]. Un
/// écran monté sur un faux dépôt n'a besoin ni de réseau, ni de session, ni de
/// base — les tests de ce dossier ne simulent pas Supabase, ils ne le
/// rencontrent jamais.
///
/// QUATRE LECTURES ET DEUX GESTES. Les deux gestes — accepter, refuser —
/// passent par `accepter_demande()` et `refuser_demande()` (015), qui sont
/// `SECURITY DEFINER` et vérifient elles-mêmes que la salle est bien celle du
/// demandeur. La contre-proposition du §5.2 n'est pas ici : c'est un geste à
/// part, avec sa saisie, et il viendra à son étape.
///
/// LES GARDE-FOUS SONT EN BASE, PAS ICI. `owner_venues()` ne connaît que
/// `auth.uid()` ; toutes les autres refusent une salle ou une demande qui n'est
/// pas la vôtre. Vérifier une seconde fois en Dart ferait un deuxième gardien
/// pour la même règle — et celui-là, un client modifié pourrait le contourner.
/// Ce que l'écran cache, il le cache pour ne pas proposer un geste qui
/// échouerait, jamais pour empêcher qu'il réussisse.
abstract interface class OwnerRepository {
  /// Les salles du propriétaire connecté, dans l'ordre du sélecteur.
  Future<List<SalleDuProprietaire>> salles();

  /// Les indicateurs d'une salle pour un mois — le mois en cours par défaut.
  Future<IndicateursSalle> indicateurs(String venueId, {DateTime? mois});

  /// Les demandes en attente d'une salle, la plus récente en tête.
  Future<List<DemandeEnAttente>> demandesEnAttente(String venueId);

  /// Le détail d'une demande, du point de vue du propriétaire.
  Future<DemandeDetail> detail(String bookingId);

  /// Accepte une demande : `pending` → `accepted`, option de 72 h (§5.1).
  Future<void> accepter(String bookingId);

  /// Refuse une demande, avec un motif facultatif.
  Future<void> refuser(String bookingId, {String? motif});

  /// Confirme avoir reçu l'acompte en main propre (§3, écran 6).
  ///
  /// Le même aboutissement que Chargily : le paiement passe « paid » et la
  /// réservation est confirmée par `confirm_booking()`. Il n'y a qu'un chemin
  /// vers « confirmed », et c'est pour cela que l'index du §6.1 protège
  /// celui-ci aussi.
  Future<void> confirmerEncaissementEspeces(String bookingId);

  /// L'agenda d'une salle sur un mois : un état par jour et par créneau.
  Future<AgendaDuMois> agenda(String venueId, DateTime mois);

  /// Ferme un créneau, avec un motif facultatif — la note privée du
  /// propriétaire.
  Future<void> bloquer(
    String venueId,
    DateTime jour,
    Creneau creneau, {
    String? motif,
  });

  /// Rouvre un créneau fermé.
  Future<void> debloquer(String venueId, DateTime jour, Creneau creneau);

  /// Inscrit une salle en brouillon, avec ses équipements et ses types.
  ///
  /// Rend l'identifiant de la salle créée : c'est lui qui mène au
  /// récapitulatif, et c'est lui dont les photos auront besoin au J13 pour
  /// leur chemin de Storage.
  Future<String> creerSalle(NouvelleSalle salle);

  /// Les photos d'une salle, dans l'ordre d'affichage (§4.3, OWN-02).
  Future<List<PhotoDeSalle>> photos(String venueId);

  /// Téléverse une photo compressée, puis l'attache à la fin de la galerie.
  ///
  /// Deux gestes, dans cet ordre : le fichier dans le bucket, la ligne ensuite.
  Future<PhotoDeSalle> ajouterPhoto(String venueId, PhotoCompressee photo);

  /// Retire une photo : la ligne, puis le fichier.
  Future<void> supprimerPhoto(String photoId);

  /// Réécrit l'ordre complet de la galerie. La première devient la couverture.
  Future<List<PhotoDeSalle>> reordonnerPhotos(
    String venueId,
    List<String> photoIds,
  );

  /// Envoie un brouillon à la validation humaine : `draft` → `pending`.
  ///
  /// [telephone] est le numéro auquel joindre le propriétaire : ADM-01 exige
  /// un « propriétaire joignable », et `envoyer_salle_en_validation()` (020)
  /// l'écrit dans `profiles.phone` avant de changer le statut. Il refuse sans
  /// lui — la salle reste alors un brouillon.
  Future<void> envoyerEnValidation(String venueId, String telephone);
}

/// Celui qui appelle vraiment les fonctions de 014.
class OwnerRepositorySupabase implements OwnerRepository {
  /// Crée le dépôt autour d'un client Supabase.
  const OwnerRepositorySupabase(this._client);

  final SupabaseClient _client;

  @override
  Future<List<SalleDuProprietaire>> salles() async {
    final lignes = await _client.rpc<List<dynamic>>('owner_venues');

    return lignes
        .cast<Map<String, dynamic>>()
        .map(SalleDuProprietaire.depuisJson)
        .toList(growable: false);
  }

  /// [mois] n'est pas passé par l'écran 9, qui ne montre qu'aujourd'hui. Le
  /// paramètre existe parce que la fonction SQL l'accepte, et qu'un sélecteur
  /// de mois est la suite naturelle de cet écran : le jour où il arrivera, il
  /// n'y aura rien à changer sous lui.
  @override
  Future<IndicateursSalle> indicateurs(String venueId, {DateTime? mois}) async {
    final lignes = await _client.rpc<List<dynamic>>(
      'owner_dashboard',
      params: <String, dynamic>{
        'p_venue_id': venueId,
        if (mois != null) 'p_month': _premierDuMois(mois),
      },
    );

    if (lignes.isEmpty) {
      // Ne devrait pas arriver : `owner_dashboard()` rend toujours une ligne,
      // ou lève. Un tableau vide voudrait dire que la fonction a changé de
      // forme — mieux vaut le dire que d'afficher un écran de zéros.
      throw StateError(
        'owner_dashboard() n’a renvoyé aucune ligne pour la salle $venueId.',
      );
    }

    return IndicateursSalle.depuisJson(lignes.first as Map<String, dynamic>);
  }

  @override
  Future<List<DemandeEnAttente>> demandesEnAttente(String venueId) async {
    final lignes = await _client.rpc<List<dynamic>>(
      'owner_pending_requests',
      params: <String, dynamic>{'p_venue_id': venueId},
    );

    return lignes
        .cast<Map<String, dynamic>>()
        .map(DemandeEnAttente.depuisJson)
        .toList(growable: false);
  }

  @override
  Future<DemandeDetail> detail(String bookingId) async {
    final lignes = await _client.rpc<List<dynamic>>(
      'owner_request_detail',
      params: <String, dynamic>{'p_booking_id': bookingId},
    );

    if (lignes.isEmpty) {
      // La fonction lève sur une demande inconnue ou étrangère ; un tableau
      // vide voudrait dire qu'elle a changé de forme.
      throw StateError(
        'owner_request_detail() n’a renvoyé aucune ligne pour $bookingId.',
      );
    }

    return DemandeDetail.depuisJson(lignes.first as Map<String, dynamic>);
  }

  /// L'acompte n'est pas passé : `accepter_demande()` applique `deposit_rate()`
  /// au devis déjà en base. Le taux du §5.3 vit à un seul endroit, et ce n'est
  /// pas ici.
  @override
  Future<void> accepter(String bookingId) async {
    await _client.rpc<List<dynamic>>(
      'accepter_demande',
      params: <String, dynamic>{'p_booking_id': bookingId},
    );
  }

  @override
  Future<void> refuser(String bookingId, {String? motif}) async {
    await _client.rpc<List<dynamic>>(
      'refuser_demande',
      params: <String, dynamic>{'p_booking_id': bookingId, 'p_motif': motif},
    );
  }

  @override
  Future<void> confirmerEncaissementEspeces(String bookingId) async {
    await _client.rpc<dynamic>(
      'confirmer_encaissement_especes',
      params: <String, dynamic>{'p_booking_id': bookingId},
    );
  }

  @override
  Future<AgendaDuMois> agenda(String venueId, DateTime mois) async {
    final lignes = await _client.rpc<List<dynamic>>(
      'owner_agenda',
      params: <String, dynamic>{
        'p_venue_id': venueId,
        'p_month': _premierDuMois(mois),
      },
    );

    return AgendaDuMois.depuisLignes(mois, lignes.cast<Map<String, dynamic>>());
  }

  /// Le refus de fermer un créneau vendu n'est PAS vérifié ici.
  ///
  /// `bloquer_date()` (016) le refuse elle-même, avec un code Ferha que
  /// `messageErreurAgenda` traduit. Regarder l'état affiché avant d'appeler
  /// ferait un second gardien pour la même règle — et celui-là mentirait dès
  /// que l'écran aurait une seconde de retard sur la base, ce qui est
  /// exactement le cas qu'on veut couvrir.
  @override
  Future<void> bloquer(
    String venueId,
    DateTime jour,
    Creneau creneau, {
    String? motif,
  }) async {
    await _client.rpc<List<dynamic>>(
      'bloquer_date',
      params: <String, dynamic>{
        'p_venue_id': venueId,
        'p_date': dateVersIso(jour),
        'p_creneau': creneau.code,
        'p_motif': motif,
      },
    );
  }

  @override
  Future<void> debloquer(String venueId, DateTime jour, Creneau creneau) async {
    await _client.rpc<List<dynamic>>(
      'debloquer_date',
      params: <String, dynamic>{
        'p_venue_id': venueId,
        'p_date': dateVersIso(jour),
        'p_creneau': creneau.code,
      },
    );
  }

  /// UN SEUL APPEL POUR LA SALLE, SES ÉQUIPEMENTS ET SES TYPES. `creer_salle()`
  /// (019) écrit les trois dans une seule transaction : ou tout passe, ou rien.
  /// Trois appels depuis ici laisseraient, sur une 4G qui coupe (§7.3), une
  /// salle sans équipements que le propriétaire recréerait en double.
  ///
  /// NI LE PROPRIÉTAIRE NI LE STATUT NE SONT ENVOYÉS : la fonction lit
  /// `auth.uid()` et écrit « draft » en dur. Il n'y a donc rien à mentir depuis
  /// ici, et ce n'est pas une politesse — c'est ce qui rend « créer une salle au
  /// nom d'un autre » inexprimable.
  @override
  Future<String> creerSalle(NouvelleSalle salle) async {
    final lignes = await _client.rpc<List<dynamic>>(
      'creer_salle',
      params: <String, dynamic>{
        'p_name': salle.nom.trim(),
        'p_wilaya_code': salle.wilayaCode,
        'p_commune': salle.commune.trim(),
        'p_address': salle.adresse.trim(),
        'p_capacity_seated': salle.capacite,
        'p_area_sqm': salle.superficie,
        // Envoyé tel quel, `null` compris : « non renseigné » et « aucune
        // place » ne se disent pas pareil (§6), et les confondre ici ferait
        // afficher « 0 place » sur une salle dont on ne sait rien.
        'p_parking_spaces': salle.parking,
        'p_description': salle.description.trim(),
        'p_amenities': salle.equipements.toList(growable: false),
        'p_event_types': salle.typesEvenement.toList(growable: false),
      },
    );

    if (lignes.isEmpty) {
      // `creer_salle()` rend toujours une ligne, ou lève. Un tableau vide
      // voudrait dire qu'elle a changé de forme — et l'écran naviguerait vers
      // un récapitulatif sans identifiant.
      throw StateError('creer_salle() n’a renvoyé aucune ligne.');
    }

    return (lignes.first as Map<String, dynamic>)['id'] as String;
  }

  /// LA GALERIE SE LIT DIRECTEMENT DANS LA TABLE, sans fonction SQL, et c'est
  /// le seul endroit de ce dépôt qui le fait. Ailleurs on passe par une RPC
  /// parce qu'il y a quelque chose à assembler ou une règle à faire respecter ;
  /// ici il n'y a qu'à lire quatre colonnes d'une table dont la politique
  /// `venue_photos_select` (002) dit déjà exactement qui voit quoi. Une fonction
  /// de plus ne ferait que redire `select ... order by position`.
  @override
  Future<List<PhotoDeSalle>> photos(String venueId) async {
    final lignes = await _client
        .from('venue_photos')
        .select('id, storage_path, position, is_cover')
        .eq('venue_id', venueId)
        .order('position');

    return lignes.map(PhotoDeSalle.depuisJson).toList(growable: false);
  }

  /// LE FICHIER D'ABORD, LA LIGNE ENSUITE, et le ménage si la seconde échoue.
  ///
  /// L'ordre inverse — la ligne puis le fichier — laisserait, le temps de
  /// l'envoi, une galerie qui montre une photo qui n'existe pas. Dans cet
  /// ordre-ci, l'accident laisse au pire un fichier que personne ne voit ; et
  /// comme on peut faire mieux que « au pire », le `catch` le retire.
  ///
  /// LE NOM DU FICHIER SUIT LE FORMAT RÉELLEMENT PRODUIT. `cheminDePhoto()`
  /// prend le format en paramètre parce que le WebP n'est pas garanti : un
  /// navigateur qui ne sait pas l'encoder donne du JPEG, et le fichier s'appelle
  /// alors `.jpg`. Le `contentType` vient de la même source — le bucket (021)
  /// n'accepte que `image/webp` et `image/jpeg`, et refuserait un en-tête qui
  /// ne correspond pas.
  @override
  Future<PhotoDeSalle> ajouterPhoto(
    String venueId,
    PhotoCompressee photo,
  ) async {
    final chemin = cheminDePhoto(venueId, photo.format);
    final bucket = _client.storage.from(_bucketDesPhotos);

    await bucket.uploadBinary(
      chemin,
      photo.octets,
      // `upsert: false` : un chemin porte un uuid neuf à chaque envoi, deux
      // photos ne peuvent pas se marcher dessus. Si cela arrivait quand même,
      // mieux vaut un refus qu'une photo écrasée en silence.
      fileOptions: FileOptions(contentType: photo.format.typeMime),
    );

    try {
      final lignes = await _client.rpc<List<dynamic>>(
        'ajouter_photo',
        params: <String, dynamic>{
          'p_venue_id': venueId,
          'p_storage_path': chemin,
        },
      );

      if (lignes.isEmpty) {
        throw StateError('ajouter_photo() n’a renvoyé aucune ligne.');
      }

      return PhotoDeSalle.depuisJson(lignes.first as Map<String, dynamic>);
    } on Object {
      // La 21e photo (FE038), une salle qui n'est plus la vôtre, un réseau qui
      // coupe : le fichier est déjà là et plus rien ne le désigne. On le retire
      // avant de laisser passer le refus, qui reste celui que l'écran doit
      // afficher — d'où le `rethrow` et non un second échec.
      try {
        await bucket.remove(<String>[chemin]);
      } on Object catch (_) {
        // Le ménage a échoué à son tour. Il ne remplace pas le refus d'origine,
        // qui est la seule chose que le propriétaire a besoin de savoir.
      }
      rethrow;
    }
  }

  /// LA LIGNE D'ABORD, LE FICHIER ENSUITE — l'inverse de l'ajout, et pour la
  /// même raison : on préfère toujours la panne qu'on ne voit pas.
  ///
  /// Si le réseau coupe entre les deux, il reste un fichier orphelin dans le
  /// bucket : deux cents kilo-octets que personne ne regarde. L'ordre inverse
  /// laisserait un trou dans la galerie d'une salle publiée, visible de tous.
  ///
  /// C'est `supprimer_photo()` (021) qui rend le chemin : le SQL ne touche pas
  /// au Storage, il dit seulement quel fichier va avec la ligne qu'il vient
  /// d'effacer.
  @override
  Future<void> supprimerPhoto(String photoId) async {
    final chemin = await _client.rpc<String?>(
      'supprimer_photo',
      params: <String, dynamic>{'p_photo_id': photoId},
    );

    if (chemin == null || chemin.isEmpty) return;

    // Une photo de démonstration porte une URL complète et non un chemin de
    // bucket (voir `urlPhoto()`) : il n'y a alors aucun fichier à nous à
    // effacer.
    if (chemin.startsWith('http')) return;

    await _client.storage.from(_bucketDesPhotos).remove(<String>[chemin]);
  }

  /// L'ORDRE COMPLET, ET NON « CETTE PHOTO PASSE EN TROISIÈME ». C'est ce
  /// qu'attend `reordonner_photos()` (021), qui refuse une liste partielle
  /// (FE040) — et ce refus est justement ce qui protège une photo ajoutée
  /// depuis un second appareil pendant qu'on réordonnait sur le premier.
  @override
  Future<List<PhotoDeSalle>> reordonnerPhotos(
    String venueId,
    List<String> photoIds,
  ) async {
    final lignes = await _client.rpc<List<dynamic>>(
      'reordonner_photos',
      params: <String, dynamic>{'p_venue_id': venueId, 'p_photo_ids': photoIds},
    );

    return lignes
        .cast<Map<String, dynamic>>()
        .map(PhotoDeSalle.depuisJson)
        .toList(growable: false);
  }

  /// LE NUMÉRO PART TEL QUE LE PROPRIÉTAIRE L'A TAPÉ, espaces compris : c'est
  /// `telephone_normalise()` (020) qui les retire, en base, pour que les deux
  /// écrans qui écrivent un numéro le rangent forcément pareil. Le nettoyer ici
  /// ferait un second endroit où la forme est décidée.
  @override
  Future<void> envoyerEnValidation(String venueId, String telephone) async {
    await _client.rpc<List<dynamic>>(
      'envoyer_salle_en_validation',
      params: <String, dynamic>{'p_venue_id': venueId, 'p_phone': telephone},
    );
  }

  /// Le bucket du §7.3. Il est écrit ici et dans `urlPhoto()`, qui le lit pour
  /// résoudre un chemin en URL publique ; les deux se répondent.
  static const String _bucketDesPhotos = 'venue-photos';

  /// `date` en SQL n'a pas d'heure : on envoie le premier du mois, en clair.
  static String _premierDuMois(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-01';
}

/// Le dépôt de l'espace propriétaire.
final ownerRepositoryProvider = Provider<OwnerRepository>(
  (ref) => OwnerRepositorySupabase(ref.watch(supabaseClientProvider)),
);
