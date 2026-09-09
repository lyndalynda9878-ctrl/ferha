import 'package:ferha/core/preferences/preferences_affichage.dart';
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
class DepotDeTest implements OwnerRepository {
  /// Crée le dépôt.
  DepotDeTest({
    this.sallesRendues = const <SalleDuProprietaire>[],
    this.indicateursRendus = const <String, IndicateursSalle>{},
    this.demandesRendues = const <String, List<DemandeEnAttente>>{},
  });

  /// Ce que rend `owner_venues()`.
  final List<SalleDuProprietaire> sallesRendues;

  /// Ce que rend `owner_dashboard()`, par salle.
  final Map<String, IndicateursSalle> indicateursRendus;

  /// Ce que rend `owner_pending_requests()`, par salle.
  final Map<String, List<DemandeEnAttente>> demandesRendues;

  /// Le nombre d'appels à [salles].
  int appelsSalles = 0;

  @override
  Future<List<SalleDuProprietaire>> salles() async {
    appelsSalles++;
    return sallesRendues;
  }

  @override
  Future<IndicateursSalle> indicateurs(String venueId, {DateTime? mois}) async {
    final trouve = indicateursRendus[venueId];
    if (trouve == null) throw StateError('Pas d’indicateurs pour $venueId');
    return trouve;
  }

  @override
  Future<List<DemandeEnAttente>> demandesEnAttente(String venueId) async =>
      demandesRendues[venueId] ?? const <DemandeEnAttente>[];
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
