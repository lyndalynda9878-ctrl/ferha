import 'dart:async';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'package:ferha/core/preferences/preferences_affichage.dart';
import 'package:ferha/features/booking/reservation.dart';
import 'package:ferha/features/owner/compression_photo.dart';
import 'package:ferha/features/owner/creneau_agenda.dart';
import 'package:ferha/features/owner/demande_detail.dart';
import 'package:ferha/features/owner/demande_en_attente.dart';
import 'package:ferha/features/owner/indicateurs_salle.dart';
import 'package:ferha/features/owner/nouvelle_salle.dart';
import 'package:ferha/features/owner/owner_repository.dart';
import 'package:ferha/features/owner/photo_de_salle.dart';
import 'package:ferha/features/owner/salle_du_proprietaire.dart';
import 'package:ferha/features/search/search_filters.dart';

/// Les doublures de l'espace propriétaire, partagées par ses tests.
///
/// Ce fichier ne se termine pas par `_test.dart` : `flutter test` ne le lance
/// pas, il l'importe. C'est ce qui permet aux deux fichiers de tests de partir
/// des mêmes salles sans les recopier — et surtout de ne pas laisser deux
/// définitions de « une salle de test » diverger.

/// Des préférences qui ne touchent pas l'appareil.
///
/// La vraie implémentation écrit dans `localStorage` ou dans un fichier ; ici
/// c'est une variable, et c'est tout ce dont les tests ont besoin. Elle SURVIT
/// au conteneur Riverpod qui la lit, ce qui est exactement ce qu'on veut
/// vérifier : deux conteneurs successifs jouent le rôle de deux ouvertures de
/// l'application sur le même téléphone.
class PreferencesEnMemoire implements PreferencesAffichage {
  /// Crée des préférences, éventuellement déjà remplies.
  PreferencesEnMemoire([this._salle]);

  String? _salle;

  /// Ce que l'appareil retient, vu du test.
  String? get retenue => _salle;

  /// Le nombre d'écritures — pour vérifier qu'on n'en fait pas d'inutile.
  int ecritures = 0;

  @override
  Future<String?> langue() async => _langue;

  @override
  Future<void> retenirLangue(String codeLangue) async => _langue = codeLangue;

  String? _langue;

  @override
  Future<String?> salleChoisie() async => _salle;

  @override
  Future<void> retenirSalle(String? venueId) async {
    ecritures++;
    _salle = venueId;
  }
}

/// Un dépôt qui rend ce qu'on lui a donné, sans réseau ni base.
///
/// Les champs sont MODIFIABLES à dessein : un test qui vérifie que le compteur
/// se rafraîchit doit pouvoir faire répondre autre chose au second appel, comme
/// la vraie base le ferait après une acceptation.
class DepotDeTest implements OwnerRepository {
  /// Crée le dépôt.
  DepotDeTest({
    this.sallesRendues = const <SalleDuProprietaire>[],
    this.indicateursRendus = const <String, IndicateursSalle>{},
    this.demandesRendues = const <String, List<DemandeEnAttente>>{},
    this.detailsRendus = const <String, DemandeDetail>{},
    this.agendasRendus = const <String, AgendaDuMois>{},
    this.erreurDeReponse,
    this.erreurDeFermeture,
    this.erreurDePublication,
  });

  /// Ce que rend `owner_venues()`.
  List<SalleDuProprietaire> sallesRendues;

  /// Ce que rend `owner_dashboard()`, par salle.
  Map<String, IndicateursSalle> indicateursRendus;

  /// Ce que rend `owner_pending_requests()`, par salle.
  Map<String, List<DemandeEnAttente>> demandesRendues;

  /// Ce que rend `owner_request_detail()`, par demande.
  Map<String, DemandeDetail> detailsRendus;

  /// Ce que rend `owner_agenda()`, par mois — la clé est « AAAA-MM ».
  Map<String, AgendaDuMois> agendasRendus;

  /// Ce que lèvent `accepter_demande()` et `refuser_demande()`, s'il y a lieu.
  Object? erreurDeReponse;

  /// L'identifiant que rend `creer_salle()`.
  String venueCree = '5a11e000-0000-4000-a000-0000000000ff';

  /// Ce que lèvent `creer_salle()` et `envoyer_salle_en_validation()`.
  Object? erreurDePublication;

  /// Ce que lèvent `bloquer_date()` et `debloquer_date()`, s'il y a lieu.
  ///
  /// SÉPARÉE DE LA PRÉCÉDENTE, parce que les deux refus n'ont pas le même
  /// vocabulaire : FE022 ne peut pas sortir d'une acceptation, et FE013 ne peut
  /// pas sortir d'une fermeture. Un seul champ laisserait un test poser un code
  /// que la vraie base ne poserait jamais là.
  Object? erreurDeFermeture;

  /// Le nombre d'appels à [salles] — c'est lui qui dit si le compteur du
  /// sélecteur a bien été redemandé.
  int appelsSalles = 0;

  /// Le nombre d'appels à [indicateurs], [demandesEnAttente] et [detail].
  int appelsIndicateurs = 0;

  /// Voir [appelsIndicateurs].
  int appelsDemandes = 0;

  /// Voir [appelsIndicateurs].
  int appelsDetail = 0;

  /// Les demandes acceptées, dans l'ordre.
  final List<String> acceptees = <String>[];

  /// Les demandes refusées, avec leur motif.
  /// Les encaissements en espèces confirmés, dans l'ordre.
  final List<String> encaissementsConfirmes = <String>[];

  /// Les réservations marquées comme honorées, dans l'ordre.
  final List<String> honorees = <String>[];

  final List<({String id, String? motif})> refusees =
      <({String id, String? motif})>[];

  /// Le nombre d'appels à [agenda] — c'est lui qui dit si passer de midi à soir
  /// a redemandé le mois, ce qu'il ne doit jamais faire.
  int appelsAgenda = 0;

  /// Les créneaux fermés, dans l'ordre.
  final List<({String venueId, DateTime jour, Creneau creneau, String? motif})>
  fermes =
      <({String venueId, DateTime jour, Creneau creneau, String? motif})>[];

  /// Les créneaux rouverts, dans l'ordre.
  final List<({String venueId, DateTime jour, Creneau creneau})> rouverts =
      <({String venueId, DateTime jour, Creneau creneau})>[];

  /// Les salles inscrites, telles que l'écran les a composées.
  ///
  /// C'est ce que regardent les tests du formulaire : ce qui ARRIVE au dépôt,
  /// et non ce que l'écran affiche. Un champ facultatif laissé vide doit
  /// arriver à `null`, et un parking à zéro doit arriver à zéro.
  final List<NouvelleSalle> inscrites = <NouvelleSalle>[];

  /// Les salles envoyées à la validation, avec le numéro qui les accompagnait.
  ///
  /// Le numéro est gardé parce que c'est lui que le test regarde : il doit
  /// arriver au dépôt tel qu'il a été tapé, espaces compris — c'est
  /// `telephone_normalise()` (020) qui les retire, en base et à un seul endroit.
  final List<({String venueId, String telephone})> envoyees =
      <({String venueId, String telephone})>[];

  @override
  Future<List<SalleDuProprietaire>> salles() async {
    appelsSalles++;
    return sallesRendues;
  }

  @override
  Future<IndicateursSalle> indicateurs(String venueId, {DateTime? mois}) async {
    appelsIndicateurs++;
    final trouve = indicateursRendus[venueId];
    if (trouve == null) throw StateError('Pas d’indicateurs pour $venueId');
    return trouve;
  }

  @override
  Future<List<DemandeEnAttente>> demandesEnAttente(String venueId) async {
    appelsDemandes++;
    return demandesRendues[venueId] ?? const <DemandeEnAttente>[];
  }

  @override
  Future<DemandeDetail> detail(String bookingId) async {
    appelsDetail++;
    final trouve = detailsRendus[bookingId];
    if (trouve == null) throw StateError('Pas de détail pour $bookingId');
    return trouve;
  }

  @override
  Future<void> accepter(String bookingId) async {
    if (erreurDeReponse != null) throw erreurDeReponse!;
    acceptees.add(bookingId);
  }

  @override
  Future<void> refuser(String bookingId, {String? motif}) async {
    if (erreurDeReponse != null) throw erreurDeReponse!;
    refusees.add((id: bookingId, motif: motif));
  }

  @override
  Future<void> confirmerEncaissementEspeces(String bookingId) async {
    if (erreurDeReponse != null) throw erreurDeReponse!;
    encaissementsConfirmes.add(bookingId);
  }

  @override
  Future<void> marquerHonoree(String bookingId) async {
    if (erreurDeReponse != null) throw erreurDeReponse!;
    honorees.add(bookingId);
  }

  @override
  Future<AgendaDuMois> agenda(String venueId, DateTime mois) async {
    appelsAgenda++;
    return agendasRendus[cleDuMois(mois)] ??
        AgendaDuMois(mois: DateTime(mois.year, mois.month), parJour: const {});
  }

  @override
  Future<void> bloquer(
    String venueId,
    DateTime jour,
    Creneau creneau, {
    String? motif,
  }) async {
    if (erreurDeFermeture != null) throw erreurDeFermeture!;
    fermes.add((venueId: venueId, jour: jour, creneau: creneau, motif: motif));
  }

  @override
  Future<void> debloquer(String venueId, DateTime jour, Creneau creneau) async {
    if (erreurDeFermeture != null) throw erreurDeFermeture!;
    rouverts.add((venueId: venueId, jour: jour, creneau: creneau));
  }

  @override
  Future<String> creerSalle(NouvelleSalle salle) async {
    if (erreurDePublication != null) throw erreurDePublication!;
    inscrites.add(salle);
    return venueCree;
  }

  @override
  Future<void> envoyerEnValidation(String venueId, String telephone) async {
    if (erreurDePublication != null) throw erreurDePublication!;
    envoyees.add((venueId: venueId, telephone: telephone));
  }

  // ---------------------------------------------------------------------------
  // Les photos (§4.3, OWN-02)
  //
  // CETTE MOITIÉ-LÀ DU DÉPÔT NE SE CONTENTE PAS DE RENDRE CE QU'ON LUI A DONNÉ :
  // elle REJOUE les règles de rang de la migration 021. Les trois autres
  // lectures sont des consultations, et une doublure peut y répondre par une
  // constante ; ici, ce que l'écran affiche dépend de ce que la base a écrit —
  // la photo qu'on déplace en tête devient la couverture, et supprimer la
  // première en donne une nouvelle. Une doublure qui rendrait une liste figée
  // laisserait passer un écran qui n'affiche jamais la bonne couverture.
  //
  // La règle rejouée est exactement celle du `check (is_cover = (position = 0))`
  // et des deux fonctions qui renumérotent : rangs contigus à partir de zéro,
  // couverture au rang zéro, et nulle part ailleurs.
  // ---------------------------------------------------------------------------

  /// La galerie de chaque salle, dans l'ordre.
  final Map<String, List<PhotoDeSalle>> galeries =
      <String, List<PhotoDeSalle>>{};

  /// Ce que lèvent les quatre gestes sur les photos, s'il y a lieu.
  ///
  /// SÉPARÉE DES DEUX AUTRES ERREURS, pour la même raison qu'elles le sont
  /// entre elles : FE038 ne peut pas sortir d'une acceptation de demande, et
  /// FE013 ne peut pas sortir d'un ajout de photo.
  Object? erreurDePhotos;

  /// De quoi retenir un envoi EN VOL, le temps de regarder l'écran.
  ///
  /// Sans elle, aucun test ne peut voir un envoi en cours : la doublure répond
  /// dans le même tour de boucle, et la photo est déjà arrivée au premier
  /// `pump`. Or « Continuer » doit rester éteint TANT QU'un envoi n'est pas
  /// fini — c'est une règle qui ne vit qu'entre deux instants, et il faut donc
  /// pouvoir tenir l'un des deux.
  Completer<void>? envoiRetenu;

  /// Les photos envoyées, avec le format réellement produit.
  final List<({String venueId, FormatPhoto format, int octets})>
  envoyeesPhotos = <({String venueId, FormatPhoto format, int octets})>[];

  /// Les ordres reçus par `reordonner_photos()`.
  final List<List<String>> ordresRecus = <List<String>>[];

  /// Les photos supprimées, dans l'ordre.
  final List<String> supprimees = <String>[];

  int _photosCreees = 0;

  @override
  Future<List<PhotoDeSalle>> photos(String venueId) async {
    if (erreurDePhotos != null) throw erreurDePhotos!;
    return List<PhotoDeSalle>.unmodifiable(
      galeries[venueId] ?? const <PhotoDeSalle>[],
    );
  }

  @override
  Future<PhotoDeSalle> ajouterPhoto(
    String venueId,
    PhotoCompressee photo,
  ) async {
    if (erreurDePhotos != null) throw erreurDePhotos!;
    if (envoiRetenu != null) await envoiRetenu!.future;

    envoyeesPhotos.add((
      venueId: venueId,
      format: photo.format,
      octets: photo.octets.lengthInBytes,
    ));

    final galerie = galeries.putIfAbsent(venueId, () => <PhotoDeSalle>[]);
    final rang = galerie.length;
    // UN PRÉFIXE QUI N'EST PAS CELUI DE `photoDeTest()`, et ce n'est pas une
    // coquetterie : une photo envoyée pendant le test ne doit pas hériter de
    // l'identifiant d'une photo qui était déjà là. Deux `photo-0` dans la même
    // galerie donnent deux `ValueKey` identiques dans le `ReorderableListView`,
    // et Flutter lève « Multiple widgets used the same GlobalKey ».
    final ajoutee = PhotoDeSalle(
      id: 'photo-envoyee-${_photosCreees++}',
      chemin: cheminDePhoto(venueId, photo.format),
      position: rang,
      estCouverture: rang == 0,
    );
    galerie.add(ajoutee);
    return ajoutee;
  }

  @override
  Future<void> supprimerPhoto(String photoId) async {
    if (erreurDePhotos != null) throw erreurDePhotos!;
    supprimees.add(photoId);

    for (final entree in galeries.entries) {
      if (entree.value.any((p) => p.id == photoId)) {
        entree.value.removeWhere((p) => p.id == photoId);
        galeries[entree.key] = _renumerote(entree.value);
        return;
      }
    }
  }

  @override
  Future<List<PhotoDeSalle>> reordonnerPhotos(
    String venueId,
    List<String> photoIds,
  ) async {
    if (erreurDePhotos != null) throw erreurDePhotos!;
    ordresRecus.add(List<String>.unmodifiable(photoIds));

    final galerie = galeries[venueId] ?? <PhotoDeSalle>[];
    final rangees = <PhotoDeSalle>[
      for (final id in photoIds) galerie.firstWhere((p) => p.id == id),
    ];

    galeries[venueId] = _renumerote(rangees);
    return List<PhotoDeSalle>.unmodifiable(galeries[venueId]!);
  }

  /// Rangs 0..n-1, et la couverture au rang zéro — la règle de 021.
  static List<PhotoDeSalle> _renumerote(List<PhotoDeSalle> photos) =>
      <PhotoDeSalle>[
        for (final (index, photo) in photos.indexed)
          PhotoDeSalle(
            id: photo.id,
            chemin: photo.chemin,
            position: index,
            estCouverture: index == 0,
          ),
      ];
}

/// Une photo déjà en base.
PhotoDeSalle photoDeTest({
  required String id,
  required int position,
  String? chemin,
}) => PhotoDeSalle(
  id: id,
  chemin: chemin ?? 'salle/$id.webp',
  position: position,
  estCouverture: position == 0,
);

/// Une galerie de [nombre] photos, rangées comme la base les rendrait.
List<PhotoDeSalle> galerieDeTest(int nombre) => <PhotoDeSalle>[
  for (var i = 0; i < nombre; i++) photoDeTest(id: 'photo-$i', position: i),
];

/// Un sélecteur qui rend des fichiers en mémoire, sans appareil ni galerie.
///
/// [XFile.fromData] fabrique un fichier qui n'existe nulle part : ses octets
/// sont dans la mémoire du test. C'est exactement ce dont l'écran a besoin — il
/// ne fait que `readAsBytes()`.
class SelecteurDeTest implements SelecteurDePhotos {
  /// Crée le sélecteur.
  SelecteurDeTest({this.aRendre = 1, this.octets = const <int>[1, 2, 3, 4]});

  /// Le nombre de photos que rend [galerie].
  int aRendre;

  /// Ce que contient chaque fichier rendu.
  List<int> octets;

  /// Le dernier maximum demandé par l'écran — c'est lui qui dit si la borne de
  /// vingt photos a bien été calculée.
  int? dernierMaximum;

  /// Le nombre d'ouvertures de l'appareil photo.
  int ouverturesAppareil = 0;

  @override
  Future<XFile?> appareilPhoto() async {
    ouverturesAppareil++;
    return XFile.fromData(Uint8List.fromList(octets), name: 'prise.jpg');
  }

  @override
  Future<List<XFile>> galerie({required int maximum}) async {
    dernierMaximum = maximum;
    return <XFile>[
      for (var i = 0; i < aRendre; i++)
        XFile.fromData(Uint8List.fromList(octets), name: 'choisie-$i.jpg'),
    ];
  }
}

/// Une compression qui ne compresse rien, et rend le format qu'on lui dit.
///
/// Elle existe parce que la vraie appelle un encodeur natif sur Android et un
/// canevas sur le web, et que `flutter test` n'a ni l'un ni l'autre. Ce qu'elle
/// garde du contrat, c'est ce qui compte pour l'écran : un [FormatPhoto] qui
/// voyage avec les octets jusqu'au nom du fichier.
class CompresseurDeTest implements CompresseurDePhoto {
  /// Crée le compresseur.
  CompresseurDeTest({this.format = FormatPhoto.webp, this.erreur});

  /// Le format que la doublure prétend avoir produit.
  FormatPhoto format;

  /// Ce qu'elle lève, s'il y a lieu.
  Object? erreur;

  /// Le nombre de compressions demandées.
  int appels = 0;

  @override
  Future<PhotoCompressee> compresser(Uint8List origine) async {
    appels++;
    if (erreur != null) throw erreur!;
    return PhotoCompressee(octets: origine, format: format);
  }
}

/// « AAAA-MM » — la clé d'[DepotDeTest.agendasRendus].
String cleDuMois(DateTime mois) =>
    '${mois.year.toString().padLeft(4, '0')}-'
    '${mois.month.toString().padLeft(2, '0')}';

/// Un agenda de test : tout est libre, sauf ce qu'on précise.
///
/// [particuliers] est indexé par « quantième-créneau » — « 14-soir » — parce
/// que c'est ainsi qu'un test se lit : « le 14 au soir est confirmé ». Le reste
/// du mois est rempli de créneaux libres, comme le fait `owner_agenda()`, qui
/// rend la grille complète.
AgendaDuMois agendaDeTest(
  DateTime mois, {
  Map<String, CreneauAgenda> particuliers = const <String, CreneauAgenda>{},
}) {
  final premier = DateTime(mois.year, mois.month);
  final nombreDeJours = DateTime(premier.year, premier.month + 1, 0).day;

  final parJour = <int, Map<String, CreneauAgenda>>{};
  for (var q = 1; q <= nombreDeJours; q++) {
    for (final creneau in <Creneau>[Creneau.midi, Creneau.soir]) {
      final particulier = particuliers['$q-${creneau.code}'];
      (parJour[q] ??= <String, CreneauAgenda>{})[creneau.code] =
          particulier ??
          CreneauAgenda(
            jour: DateTime(premier.year, premier.month, q),
            creneau: creneau,
            etat: EtatAgenda.libre,
          );
    }
  }

  return AgendaDuMois(mois: premier, parJour: parJour);
}

/// Une salle du sélecteur.
SalleDuProprietaire salleDeTest({
  required String id,
  String nom = 'Salle El Bahia',
  String commune = 'Oran',
  String? wilayaNom = 'Oran',
  StatutSalle statut = StatutSalle.publiee,
  int demandesEnAttente = 0,
}) => SalleDuProprietaire(
  id: id,
  nom: nom,
  commune: commune,
  wilayaNom: wilayaNom,
  statut: statut,
  demandesEnAttente: demandesEnAttente,
);

/// Un jeu d'indicateurs, tout en valeurs par défaut sauf ce qu'on précise.
IndicateursSalle indicateursDeTest({
  DateTime? mois,
  double? tauxOccupation = 0.68,
  double? variationOccupation = 9,
  num revenu = 1840000,
  int datesVendues = 12,
  double? variationRevenu = 0.14,
  double? note = 4.6,
  int nombreAvis = 34,
  double? tauxAcceptation = 0.41,
  double? variationAcceptation = -6,
  int demandesTranchees = 17,
  int demandesEnAttente = 0,
}) => IndicateursSalle(
  mois: mois ?? DateTime(2026, 9),
  tauxOccupation: tauxOccupation,
  variationOccupation: variationOccupation,
  revenu: revenu,
  datesVendues: datesVendues,
  variationRevenu: variationRevenu,
  note: note,
  nombreAvis: nombreAvis,
  tauxAcceptation: tauxAcceptation,
  variationAcceptation: variationAcceptation,
  demandesTranchees: demandesTranchees,
  demandesEnAttente: demandesEnAttente,
);

/// Une demande en attente.
DemandeEnAttente demandeDeTest({
  required String id,
  String client = 'Amina K.',
  DateTime? date,
  Creneau creneau = Creneau.soir,
  int invites = 300,
  String? typeEvenement = 'Mariage',
  num montant = 205000,
  DateTime? creeLe,
}) => DemandeEnAttente(
  groupId: 'grp-$id',
  bookingId: 'bkg-$id',
  client: client,
  date: date ?? DateTime(2027, 8, 14),
  creneau: creneau,
  invites: invites,
  typeEvenement: typeEvenement,
  montant: montant,
  creeLe: creeLe ?? DateTime.now().subtract(const Duration(hours: 2)),
);

/// Le détail d'une demande, tel que le rend `owner_request_detail()`.
DemandeDetail detailDeTest({
  required String id,
  required String venueId,
  String salle = 'Salle El Bahia',
  String client = 'Amina Kaddour',
  DateTime? date,
  Creneau creneau = Creneau.soir,
  int invites = 300,
  String? typeEvenement = 'Mariage',
  String? message = 'Bonjour, nous serons environ 300, merci.',
  List<OptionChoisie> options = const <OptionChoisie>[],
  num montant = 205000,
  num? acompte,
  int? acompteDu,
  bool especesEnAttente = false,
  EtatReservation etat = EtatReservation.enAttente,
  String? motif,
  String? telephone,
  bool telephoneDisponible = false,
  DateTime? creeLe,
}) => DemandeDetail(
  groupId: 'grp-$id',
  bookingId: 'bkg-$id',
  venueId: venueId,
  salle: salle,
  client: client,
  telephone: telephone,
  telephoneDisponible: telephoneDisponible,
  date: date ?? DateTime(2027, 8, 14),
  creneau: creneau,
  invites: invites,
  typeEvenement: typeEvenement,
  message: message,
  options: options,
  montant: montant,
  acompte: acompte,
  acompteDu: acompteDu,
  especesEnAttente: especesEnAttente,
  etat: etat,
  motif: motif,
  creeLe: creeLe ?? DateTime.now().subtract(const Duration(hours: 2)),
);
