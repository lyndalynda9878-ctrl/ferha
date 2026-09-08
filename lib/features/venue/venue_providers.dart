import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_providers.dart';
import '../search/search_filters.dart';
import 'venue_detail.dart';

/// Ce qu'il faut pour ouvrir une fiche : la salle, et les critères de recherche
/// qui donnent le prix affiché en bas.
@immutable
class DemandeFiche {
  /// Crée une demande de fiche.
  const DemandeFiche({required this.venueId, this.date, this.invites});

  /// La salle à ouvrir.
  final String venueId;

  /// La date cherchée, ou `null` : c'est alors aujourd'hui qui tarife.
  final DateTime? date;

  /// Le nombre d'invités cherché.
  final int? invites;

  @override
  bool operator ==(Object other) =>
      other is DemandeFiche &&
      other.venueId == venueId &&
      other.date == date &&
      other.invites == invites;

  @override
  int get hashCode => Object.hash(venueId, date, invites);
}

/// La fiche d'une salle, prix compris.
///
/// Un seul appel : `venue_detail()` renvoie la salle, ses photos, ses
/// équipements et sa grille tarifaire déjà chiffrée. Sur un réseau algérien,
/// cinq allers-retours pour ouvrir une fiche se sentent (§7.3).
final ficheProvider = FutureProvider.autoDispose
    .family<VenueDetail, DemandeFiche>((ref, demande) async {
      final client = ref.watch(supabaseClientProvider);

      final reponse = await client.rpc<dynamic>(
        'venue_detail',
        params: <String, dynamic>{
          'p_venue_id': demande.venueId,
          'p_event_date': demande.date == null
              ? null
              : dateVersIso(demande.date!),
          'p_guest_count': demande.invites,
        },
      );

      return VenueDetail.depuisJson(reponse as Map<String, dynamic>);
    });

/// Ce qu'il faut pour lire un calendrier : la salle et le créneau.
///
/// Le créneau se choisit AVANT le jour — un 14 août libre le midi et pris le
/// soir doit se lire d'un coup d'œil, ce qui suppose de savoir de quel créneau
/// on parle.
@immutable
class DemandeCalendrier {
  /// Crée une demande de calendrier.
  const DemandeCalendrier({required this.venueId, required this.creneau});

  /// La salle.
  final String venueId;

  /// Le créneau regardé.
  final Creneau creneau;

  @override
  bool operator ==(Object other) =>
      other is DemandeCalendrier &&
      other.venueId == venueId &&
      other.creneau == creneau;

  @override
  int get hashCode => Object.hash(venueId, creneau);
}

/// Les jours occupés d'une salle, sur dix-huit mois.
///
/// La base ne renvoie QUE ce qui est pris : tout jour absent de cette carte est
/// libre. Sur dix-huit mois, cela fait quelques dizaines de lignes au lieu de
/// mille cent.
final calendrierProvider = FutureProvider.autoDispose
    .family<Map<DateTime, EtatJour>, DemandeCalendrier>((ref, demande) async {
      final client = ref.watch(supabaseClientProvider);

      final lignes = await client.rpc<List<dynamic>>(
        'venue_calendar',
        params: <String, dynamic>{
          'p_venue_id': demande.venueId,
          'p_slot': demande.creneau.code,
        },
      );

      return <DateTime, EtatJour>{
        for (final l in lignes.cast<Map<String, dynamic>>())
          DateTime.parse(l['day'] as String): switch (l['state'] as String) {
            'reserve' => EtatJour.reserve,
            _ => EtatJour.indisponible,
          },
      };
    });
