import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';
import '../search/search_filters.dart';
import '../venue/venue_detail.dart';
import 'devis_reservation.dart';

/// Ce sur quoi porte un devis : la salle, la date, le créneau, les invités et
/// les options cochées.
///
/// Immuable et comparable, comme [SearchFilters] : c'est la clé du fournisseur,
/// et recocher puis décocher la même case ne doit pas produire deux appels
/// réseau de plus.
///
/// [optionIds] est TRIÉ à la construction. Deux jeux d'options identiques
/// choisis dans un ordre différent sont le même devis, et doivent donc être la
/// même clé — sans quoi cocher A puis B et cocher B puis A demanderaient deux
/// fois la même chose à la base.
@immutable
class DemandeDevis {
  /// Crée une demande de devis.
  DemandeDevis({
    required this.venueId,
    required this.date,
    required this.creneau,
    required this.invites,
    Iterable<String> optionIds = const <String>[],
  }) : optionIds = List<String>.unmodifiable(optionIds.toList()..sort());

  /// La salle.
  final String venueId;

  /// La date de l'événement.
  final DateTime date;

  /// Le créneau demandé.
  final Creneau creneau;

  /// Le nombre d'invités.
  final int invites;

  /// Les identifiants des options cochées, triés.
  final List<String> optionIds;

  @override
  bool operator ==(Object other) =>
      other is DemandeDevis &&
      other.venueId == venueId &&
      other.date == date &&
      other.creneau == creneau &&
      other.invites == invites &&
      listEquals(other.optionIds, optionIds);

  @override
  int get hashCode =>
      Object.hash(venueId, date, creneau, invites, Object.hashAll(optionIds));
}

/// Le devis de l'écran de demande, recalculé à chaque changement.
///
/// « Le devis se recalcule à chaque option cochée » (maquettes, écran 5). Un
/// appel, un devis : rien n'est déduit d'un devis précédent, et l'application
/// n'additionne jamais deux montants elle-même.
///
/// `autoDispose` : ces devis ne servent qu'à un écran, et le jeu de clés est
/// grand — un par combinaison d'options. Les garder en mémoire après coup ne
/// ferait qu'accumuler des montants périmés.
final devisProvider = FutureProvider.autoDispose
    .family<DevisReservation, DemandeDevis>((ref, demande) async {
      final client = ref.watch(supabaseClientProvider);

      final reponse = await client.rpc<dynamic>(
        'booking_quote',
        params: <String, dynamic>{
          'p_venue_id': demande.venueId,
          'p_event_date': dateVersIso(demande.date),
          'p_slot': demande.creneau.code,
          'p_guest_count': demande.invites,
          'p_option_ids': demande.optionIds,
        },
      );

      return DevisReservation.depuisJson(reponse as Map<String, dynamic>);
    });

/// Ce qu'une demande envoyée laisse derrière elle, pour l'écran de confirmation.
///
/// Le montant vient de `bookings.quoted_amount`, c'est-à-dire du trigger
/// `bookings_set_price`, c'est-à-dire d'`estimate_price()`. On ne réaffiche pas
/// le total du devis d'écran : celui-ci pouvait dater de quelques secondes, et
/// c'est le montant écrit en base qui engage.
@immutable
class DemandeEnvoyee {
  /// Crée le récapitulatif d'une demande envoyée.
  const DemandeEnvoyee({
    required this.groupId,
    required this.salle,
    required this.localisation,
    required this.date,
    required this.creneau,
    required this.invites,
    required this.montant,
    required this.options,
    this.typeEvenement,
  });

  /// L'identifiant du groupe de réservation — une journée entière en a deux
  /// lignes, mais un seul groupe (§6.1). C'est lui la référence de la demande.
  final String groupId;

  /// Le nom de la salle.
  final String salle;

  /// « Bir El Djir, Oran (31) ».
  final String localisation;

  /// La date de l'événement.
  final DateTime date;

  /// Le créneau demandé.
  final Creneau creneau;

  /// Le nombre d'invités.
  final int invites;

  /// Le devis écrit en base, en dinars.
  final num montant;

  /// Les options retenues, telles que la base les a facturées.
  final List<OptionSalle> options;

  /// Le libellé du type d'événement, s'il y en avait un.
  final String? typeEvenement;

  /// Les huit premiers caractères du groupe : de quoi citer la demande au
  /// téléphone sans réciter trente-six caractères.
  String get reference => groupId.substring(0, 8).toUpperCase();
}

/// L'envoi d'une demande de réservation.
///
/// Un seul endroit qui appelle `request_booking()`. Les erreurs remontent
/// telles quelles — c'est `messageErreurDemande` qui les traduit, au moment de
/// l'affichage : une couche de service qui transforme ses exceptions en
/// chaînes fait perdre le SQLSTATE à celle qui suit.
class BookingService {
  /// Crée le service autour d'un client Supabase.
  const BookingService(this._client);

  final SupabaseClient _client;

  /// Pose la demande. C'est `request_booking()` qui fait tout le travail.
  ///
  /// La réservation naît en `pending` : rien n'est bloqué, rien n'est payé, et
  /// plusieurs familles peuvent demander le même 14 août — c'est le
  /// propriétaire qui arbitre (§5.1).
  ///
  /// AUCUN MONTANT N'EST ENVOYÉ. `request_booking()` insère `quoted_amount = 0`
  /// et le trigger `bookings_set_price` l'écrase par `estimate_price()` : même
  /// si cette méthode voulait mentir sur le prix, elle ne le pourrait pas.
  ///
  /// Une journée entière revient en deux lignes, midi et soir, qui portent le
  /// devis du GROUPE — répété, pas partagé (§6.1). On lit donc la première, et
  /// on ne somme surtout pas les deux.
  ///
  /// [telephone] EST ENVOYÉ TEL QU'IL A ÉTÉ TAPÉ, espaces compris.
  /// `request_booking()` (020) l'écrit dans `profiles.phone` après l'avoir
  /// normalisé, et refuse la demande s'il ne suit pas la règle (FE007). C'est
  /// par ce numéro que la salle rappelle une fois la demande acceptée (§9) :
  /// sans lui, `booking_contact()` ne rendrait rien au propriétaire.
  Future<DemandeEnvoyee> envoyer({
    required VenueDetail salle,
    required DateTime date,
    required Creneau creneau,
    required int invites,
    required List<OptionSalle> options,
    required String telephone,
    TypeEvenement? typeEvenement,
  }) async {
    final lignes = await _client.rpc<List<dynamic>>(
      'request_booking',
      params: <String, dynamic>{
        'p_venue_id': salle.id,
        'p_event_date': dateVersIso(date),
        'p_slot': creneau.code,
        'p_guest_count': invites,
        'p_phone': telephone,
        // Le CODE, pas le libellé : « Mariage » ne se compare pas à « زفاف ».
        'p_event_type': typeEvenement?.code,
        'p_option_ids': options.map((o) => o.id).toList(growable: false),
      },
    );

    final premiere = lignes.first as Map<String, dynamic>;

    return DemandeEnvoyee(
      groupId: premiere['group_id'] as String,
      salle: salle.nom,
      localisation: salle.localisation,
      date: DateTime.parse(premiere['event_date'] as String),
      creneau: Creneau.depuisCode(premiere['requested_slot'] as String?),
      invites: (premiere['guest_count'] as num).toInt(),
      montant: premiere['quoted_amount'] as num,
      options: options,
      typeEvenement: typeEvenement?.libelle,
    );
  }
}

/// Le service de réservation.
final bookingServiceProvider = Provider<BookingService>(
  (ref) => BookingService(ref.watch(supabaseClientProvider)),
);
