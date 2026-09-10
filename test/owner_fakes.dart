import 'package:ferha/core/preferences/preferences_affichage.dart';
import 'package:ferha/features/booking/reservation.dart';
import 'package:ferha/features/owner/demande_detail.dart';
import 'package:ferha/features/owner/demande_en_attente.dart';
import 'package:ferha/features/owner/indicateurs_salle.dart';
import 'package:ferha/features/owner/owner_repository.dart';
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
    this.erreurDeReponse,
  });

  /// Ce que rend `owner_venues()`.
  List<SalleDuProprietaire> sallesRendues;

  /// Ce que rend `owner_dashboard()`, par salle.
  Map<String, IndicateursSalle> indicateursRendus;

  /// Ce que rend `owner_pending_requests()`, par salle.
  Map<String, List<DemandeEnAttente>> demandesRendues;

  /// Ce que rend `owner_request_detail()`, par demande.
  Map<String, DemandeDetail> detailsRendus;

  /// Ce que lèvent `accepter_demande()` et `refuser_demande()`, s'il y a lieu.
  Object? erreurDeReponse;

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
  final List<({String id, String? motif})> refusees =
      <({String id, String? motif})>[];

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
  etat: etat,
  motif: motif,
  creeLe: creeLe ?? DateTime.now().subtract(const Duration(hours: 2)),
);
