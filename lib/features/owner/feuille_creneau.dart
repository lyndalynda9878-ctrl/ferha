import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/ferha_colors.dart';
import '../../core/theme/ferha_radii.dart';
import '../search/search_filters.dart';
import 'creneau_agenda.dart';
import 'owner_messages.dart';
import 'owner_providers.dart';
import 'salle_du_proprietaire.dart';

/// Ouvre la feuille d'un créneau libre ou fermé (§4.3, OWN-06).
///
/// UNE FEUILLE, PAS UNE BOÎTE DE DIALOGUE. Fermer une date demande d'écrire un
/// motif : une feuille laisse le clavier monter sans recouvrir le champ, et
/// `isScrollControlled` avec le `viewInsets` la fait remonter avec lui. Une
/// `AlertDialog` sur un téléphone se retrouve à moitié sous le clavier.
///
/// On n'ouvre jamais cette feuille sur un créneau réservé : celui-là mène à sa
/// demande. `bloquer_date()` refuserait de toute façon (FE022) — mais un écran
/// qui propose un geste perdu d'avance a déjà fait perdre son temps à quelqu'un.
Future<void> ouvrirFeuilleDeCreneau(
  BuildContext context, {
  required SalleDuProprietaire salle,
  required CreneauAgenda creneau,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _FeuilleCreneau(salle: salle, creneau: creneau),
  );
}

class _FeuilleCreneau extends ConsumerStatefulWidget {
  const _FeuilleCreneau({required this.salle, required this.creneau});

  final SalleDuProprietaire salle;
  final CreneauAgenda creneau;

  @override
  ConsumerState<_FeuilleCreneau> createState() => _FeuilleCreneauState();
}

class _FeuilleCreneauState extends ConsumerState<_FeuilleCreneau> {
  final _motif = TextEditingController();

  /// Sur quoi porte la fermeture.
  ///
  /// Le créneau touché par défaut, et la journée entière en troisième choix —
  /// c'est le cas réel du propriétaire qui ferme pour travaux, et
  /// `venue_blackouts` sait déjà l'écrire en deux lignes (§6.1). LA RÉOUVERTURE,
  /// elle, ne l'offre pas : on rouvre exactement ce qu'on a touché. Rouvrir
  /// « toute la journée » depuis une case du soir effacerait un blocage de midi
  /// que le propriétaire ne voyait pas à l'écran.
  late Creneau _portee = widget.creneau.creneau;

  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  bool get _ferme => widget.creneau.etat.seRouvre;

  Future<void> _agir() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });

    final service = ref.read(fermetureDeDateServiceProvider);
    final texte = _motif.text.trim();

    try {
      if (_ferme) {
        await service.rouvrir(
          widget.salle.id,
          widget.creneau.jour,
          widget.creneau.creneau,
        );
      } else {
        await service.fermer(
          widget.salle.id,
          widget.creneau.jour,
          _portee,
          motif: texte.isEmpty ? null : texte,
        );
      }
      if (!mounted) return;

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _ferme
                ? '${dateEnFrancais(widget.creneau.jour)} est de nouveau à '
                      'vendre.'
                : '${dateEnFrancais(widget.creneau.jour)} est fermée.',
          ),
        ),
      );
    } on Object catch (erreur) {
      if (!mounted) return;
      // LE MESSAGE RESTE DANS LA FEUILLE, et ne part pas en SnackBar. FE022 —
      // « ce créneau vient d'être réservé » — arrive précisément quand l'écran
      // avait une seconde de retard sur la base : le propriétaire doit le lire
      // là où il vient d'agir, pas dans un bandeau qui s'efface tout seul.
      setState(() => _erreur = messageErreurAgenda(erreur));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Padding(
      // Ce que le clavier recouvre, la feuille le rend en marge : le champ de
      // motif reste visible pendant qu'on le remplit.
      padding: EdgeInsetsDirectional.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsetsDirectional.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colors.rule,
                    borderRadius: FerhaRadii.chipBorder,
                  ),
                ),
              ),

              Text(
                dateEnFrancais(widget.creneau.jour),
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                '${widget.creneau.creneau.libelle} · '
                '${widget.creneau.etat.libelle.toLowerCase()}',
                style: text.bodySmall?.copyWith(color: colors.inkSecondary),
              ),
              const SizedBox(height: 20),

              if (_ferme) ..._rouvrir(context) else ..._fermer(context),

              if (_erreur != null) ...<Widget>[
                const SizedBox(height: 16),
                _Refus(message: _erreur!),
              ],

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _enCours ? null : _agir,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsetsDirectional.symmetric(
                      vertical: 16,
                    ),
                  ),
                  child: _enCours
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_ferme ? 'Rouvrir cette date' : 'Fermer la date'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Le cas « libre » : sur quoi, et pourquoi.
  List<Widget> _fermer(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return <Widget>[
      Text(
        'FERMER',
        style: text.labelSmall?.copyWith(
          color: colors.inkTertiary,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 10),
      SegmentedButton<Creneau>(
        segments: const <ButtonSegment<Creneau>>[
          ButtonSegment<Creneau>(value: Creneau.midi, label: Text('Midi')),
          ButtonSegment<Creneau>(value: Creneau.soir, label: Text('Soir')),
          ButtonSegment<Creneau>(
            value: Creneau.journee,
            label: Text('Journée'),
          ),
        ],
        selected: <Creneau>{_portee},
        onSelectionChanged: _enCours
            ? null
            : (choix) => setState(() => _portee = choix.first),
        showSelectedIcon: false,
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _motif,
        enabled: !_enCours,
        maxLines: 2,
        maxLength: 200,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Motif (facultatif)',
          hintText: 'Travaux, mariage de ma fille…',
        ),
      ),
      Text(
        // La phrase qui compte de cette feuille. Le motif de venue_blackouts
        // n'a AUCUN chemin vers un client : venue_availability ne porte que la
        // salle, la date et le créneau, et venue_calendar() que le jour et son
        // état. Le dire ici, c'est ce qui fait qu'un propriétaire l'écrit
        // vraiment — et un motif écrit est un agenda qu'on comprend six mois
        // plus tard.
        'Ce motif ne sort pas de votre agenda : les clients verront seulement '
        'que la date n’est pas disponible.',
        style: text.bodySmall?.copyWith(color: colors.inkTertiary),
      ),
    ];
  }

  /// Le cas « fermé » : ce qu'on avait noté, et de quoi revenir en arrière.
  List<Widget> _rouvrir(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final motif = widget.creneau.motif;

    return <Widget>[
      if (motif != null && motif.trim().isNotEmpty) ...<Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsetsDirectional.all(14),
          decoration: BoxDecoration(
            color: colors.surfaceSecondary,
            borderRadius: FerhaRadii.cardBorder,
            border: Border.all(color: colors.ruleSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'VOTRE MOTIF',
                style: text.labelSmall?.copyWith(
                  color: colors.inkTertiary,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(motif, style: text.bodyMedium),
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],
      Text(
        'Rouvrir remet ce créneau à vendre. Les clients pourront de nouveau le '
        'demander.',
        style: text.bodySmall?.copyWith(color: colors.inkSecondary),
      ),
    ];
  }
}

/// Le refus de la base, en toutes lettres et à côté du bouton qui l'a produit.
class _Refus extends StatelessWidget {
  const _Refus({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rouge = Theme.of(context).colorScheme.error;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: FerhaRadii.cardBorder,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 18, color: rouge),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: text.bodySmall?.copyWith(color: context.ferhaColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
