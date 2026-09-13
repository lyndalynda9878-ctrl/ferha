import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../booking/mes_reservations_providers.dart';
import '../owner/owner_providers.dart';
import '../venue/venue_providers.dart';
import 'avis.dart';
import 'avis_repository.dart';

/// Les avis d'une salle — l'écran 7.
///
/// Une famille indexée sur la salle, `autoDispose` : on en regarde une à la
/// fois, et l'écran quitté n'a pas à rester en mémoire.
///
/// AUCUN RÉESSAI AUTOMATIQUE, comme pour l'acompte (024). Riverpod 3 réessaie
/// dix fois par défaut ; « salle introuvable » n'est pas une panne, c'est une
/// réponse, et la même reviendra dix fois pendant qu'un squelette tourne.
final avisDeLaSalleProvider = FutureProvider.autoDispose
    .family<AvisDeLaSalle, String>(
      retry: (_, _) => null,
      (ref, venueId) => ref.watch(avisRepositoryProvider).deLaSalle(venueId),
    );

/// Ce qu'il faut à l'écran de dépôt d'un avis.
///
/// Même absence de réessai, et pour une raison plus forte encore : « la fenêtre
/// de dépôt n'est pas ouverte » (FE077) est une phrase que l'écran doit écrire
/// tout de suite, pas au bout de six secondes de roue qui tourne.
final avisADeposerProvider = FutureProvider.autoDispose
    .family<AvisADeposer, String>(
      retry: (_, _) => null,
      (ref, bookingId) => ref.watch(avisRepositoryProvider).aDeposer(bookingId),
    );

/// Déposer un avis, y répondre, et remettre d'aplomb ce que le geste fausse.
///
/// LE POINT DE CETTE CLASSE EST LA SECONDE MOITIÉ, comme pour
/// `ReponseADemandeService`. Appeler `deposer_avis()` est une ligne ; ce qui se
/// périme ensuite l'est moins :
///
///   * l'écran de dépôt lui-même, qui doit repasser en « Modifier mon avis » ;
///   * la page d'avis de la salle, dont la note et la liste viennent de changer ;
///   * la FICHE de la salle, qui affiche la même note en haut à gauche ;
///   * « Mes réservations », dont le bouton dépend d'`avis_possible` — et cette
///     colonne-là ne bouge PAS toute seule : le suivi client s'abonne aux
///     changements de `bookings`, et déposer un avis n'écrit pas dans
///     `bookings`. Sans ce rechargement, le bouton continuerait de dire
///     « Déposer un avis » sur un avis déjà publié.
///
/// AUCUNE VÉRIFICATION DE DROIT ICI. Les deux fonctions de 026 refusent
/// d'elles-mêmes la réservation d'un autre et la salle d'un autre. Ce service ne
/// fait que transporter, puis ranger derrière lui.
class AvisService {
  /// Crée le service.
  const AvisService(this._ref);

  final Ref _ref;

  /// Dépose l'avis d'une réservation, ou le corrige (§5.4).
  Future<void> deposer(
    AvisADeposer avis, {
    required int note,
    Map<SousNote, int> sousNotes = const <SousNote, int>{},
    String? commentaire,
  }) async {
    await _ref
        .read(avisRepositoryProvider)
        .deposer(
          bookingId: avis.bookingId,
          note: note,
          sousNotes: sousNotes,
          commentaire: commentaire,
        );

    _ref.invalidate(avisADeposerProvider(avis.bookingId));
    _ref.invalidate(avisDeLaSalleProvider(avis.venueId));
    _rafraichirLaFiche();

    // Le bouton de « Mes réservations ». Rechargé et non invalidé : la liste ne
    // doit pas retomber sur son squelette parce qu'on vient de la noter.
    await _ref.read(mesReservationsProvider.notifier).recharger();
  }

  /// Répond à un avis, une seule fois (§4.3, OWN-06).
  ///
  /// LA NOTE DU TABLEAU DE BORD NE CHANGE PAS, et l'indicateur est pourtant
  /// relu : répondre fige l'avis, et c'est le genre de chose qu'on veut voir
  /// à jour en revenant. L'appel est petit, et le propriétaire répond rarement
  /// deux fois par minute.
  Future<void> repondre(
    AvisDeLaSalle salle,
    AvisPublie avis,
    String reponse,
  ) async {
    await _ref.read(avisRepositoryProvider).repondre(avis.id, reponse);

    _ref.invalidate(avisDeLaSalleProvider(salle.venueId));
    _ref.invalidate(indicateursProvider(salle.venueId));
  }

  /// La note affichée en haut de la fiche salle vient de changer.
  ///
  /// TOUTE LA FAMILLE EST INVALIDÉE, et non la seule fiche concernée : sa clé
  /// est un triplet — salle, date, invités — dont on ne connaît ici que le
  /// premier tiers. Déposer un avis est un geste rare, et une fiche rechargée
  /// pour rien coûte un appel ; une note fausse en haut d'une fiche coûte la
  /// confiance dans toutes les autres.
  void _rafraichirLaFiche() => _ref.invalidate(ficheProvider);
}

/// Le service des avis.
final avisServiceProvider = Provider<AvisService>(AvisService.new);
