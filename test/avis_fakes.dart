import 'package:ferha/features/reviews/avis.dart';
import 'package:ferha/features/reviews/avis_repository.dart';
import 'package:ferha/features/search/search_filters.dart';

/// Les doublures des avis, partagées par leurs tests.
///
/// Ce fichier ne se termine pas par `_test.dart` : `flutter test` ne le lance
/// pas, il l'importe — comme `owner_fakes.dart`.

/// Un dépôt d'avis qui rend ce qu'on lui a donné, sans réseau ni base.
///
/// IL GARDE CE QU'ON LUI ENVOIE, et c'est ce que regardent les tests : non pas
/// ce que l'écran affiche après coup, mais ce qui ARRIVE à la base. Une
/// sous-note effacée doit arriver absente, et un commentaire vide doit arriver
/// à `null` — deux choses qu'un écran peut afficher juste tout en envoyant faux.
class DepotAvisDeTest implements AvisRepository {
  /// Crée le dépôt.
  DepotAvisDeTest({
    this.salles = const <String, AvisDeLaSalle>{},
    this.aDeposerRendus = const <String, AvisADeposer>{},
    this.erreurDeLecture,
    this.erreurDeDepot,
    this.erreurDeReponse,
  });

  /// Ce que rend `avis_de_la_salle()`, par salle.
  Map<String, AvisDeLaSalle> salles;

  /// Ce que rend `avis_a_deposer()`, par réservation.
  Map<String, AvisADeposer> aDeposerRendus;

  /// Ce que lèvent les deux lectures, s'il y a lieu.
  Object? erreurDeLecture;

  /// Ce que lève `deposer_avis()`.
  Object? erreurDeDepot;

  /// Ce que lève `repondre_a_un_avis()`.
  ///
  /// SÉPARÉE DE LA PRÉCÉDENTE : FE078 ne peut pas sortir d'une réponse, et
  /// FE082 ne peut pas sortir d'un dépôt. Un seul champ laisserait un test poser
  /// un code que la vraie base ne poserait jamais là.
  Object? erreurDeReponse;

  /// Les avis déposés, tels que l'écran les a composés.
  final List<
    ({
      String bookingId,
      int note,
      Map<SousNote, int> sousNotes,
      String? commentaire,
    })
  >
  deposes =
      <
        ({
          String bookingId,
          int note,
          Map<SousNote, int> sousNotes,
          String? commentaire,
        })
      >[];

  /// Les réponses publiées, dans l'ordre.
  final List<({String avisId, String texte})> reponses =
      <({String avisId, String texte})>[];

  @override
  Future<AvisDeLaSalle> deLaSalle(String venueId) async {
    if (erreurDeLecture != null) throw erreurDeLecture!;
    final trouve = salles[venueId];
    if (trouve == null) throw StateError('Pas d’avis pour $venueId');
    return trouve;
  }

  @override
  Future<AvisADeposer> aDeposer(String bookingId) async {
    if (erreurDeLecture != null) throw erreurDeLecture!;
    final trouve = aDeposerRendus[bookingId];
    if (trouve == null) {
      throw StateError('Pas d’avis à déposer pour $bookingId');
    }
    return trouve;
  }

  @override
  Future<void> deposer({
    required String bookingId,
    required int note,
    Map<SousNote, int> sousNotes = const <SousNote, int>{},
    String? commentaire,
  }) async {
    if (erreurDeDepot != null) throw erreurDeDepot!;
    deposes.add((
      bookingId: bookingId,
      note: note,
      sousNotes: Map<SousNote, int>.unmodifiable(sousNotes),
      commentaire: commentaire,
    ));
  }

  @override
  Future<void> repondre(String avisId, String reponse) async {
    if (erreurDeReponse != null) throw erreurDeReponse!;
    reponses.add((avisId: avisId, texte: reponse));
  }
}

/// Un avis publié, tout en valeurs par défaut sauf ce qu'on précise.
AvisPublie avisDeTest({
  required String id,
  String auteur = 'Amina H.',
  int note = 5,
  Map<SousNote, int> sousNotes = const <SousNote, int>{},
  String? commentaire = 'Salle impeccable, le parking a fait la différence.',
  DateTime? publieLe,
  String? reponse,
  DateTime? reponduLe,
}) => AvisPublie(
  id: id,
  auteur: auteur,
  note: note,
  sousNotes: sousNotes,
  commentaire: commentaire,
  publieLe: publieLe ?? DateTime(2026, 8, 20),
  reponse: reponse,
  reponduLe: reponse == null ? null : (reponduLe ?? DateTime(2026, 8, 22)),
);

/// La page d'avis d'une salle.
AvisDeLaSalle avisDeLaSalleDeTest({
  required String venueId,
  String salle = 'Salle El Bahia',
  double? note = 4.6,
  int? nombre,
  Map<SousNote, double> moyennes = const <SousNote, double>{
    SousNote.proprete: 4.8,
    SousNote.service: 4.4,
    SousNote.rapportQualitePrix: 4.2,
    SousNote.conformite: 4.7,
  },
  List<AvisPublie> avis = const <AvisPublie>[],
}) => AvisDeLaSalle(
  venueId: venueId,
  salle: salle,
  note: note,
  nombre: nombre ?? avis.length,
  moyennes: moyennes,
  avis: avis,
);

/// Ce que rend `avis_a_deposer()` — une soirée notable.
AvisADeposer aDeposerDeTest({
  required String bookingId,
  required String venueId,
  String salle = 'Salle El Bahia',
  String commune = 'Oran',
  String? wilayaNom = 'Oran',
  DateTime? date,
  Creneau creneau = Creneau.soir,
  int invites = 300,
  DateTime? ouvreLe,
  DateTime? fermeLe,
  bool fenetreOuverte = true,
  bool modifiable = true,
  String? avisId,
  int? note,
  Map<SousNote, int> sousNotes = const <SousNote, int>{},
  String? commentaire,
  String? reponse,
}) => AvisADeposer(
  groupId: 'grp-$bookingId',
  bookingId: bookingId,
  venueId: venueId,
  salle: salle,
  commune: commune,
  wilayaNom: wilayaNom,
  date: date ?? DateTime(2026, 8, 14),
  creneau: creneau,
  invites: invites,
  typeEvenement: 'Mariage',
  ouvreLe: ouvreLe ?? DateTime(2026, 8, 15),
  fermeLe: fermeLe ?? DateTime(2026, 9, 13),
  fenetreOuverte: fenetreOuverte,
  modifiable: modifiable,
  avisId: avisId,
  note: note,
  sousNotes: sousNotes,
  commentaire: commentaire,
  reponse: reponse,
  reponduLe: reponse == null ? null : DateTime(2026, 8, 22),
);
