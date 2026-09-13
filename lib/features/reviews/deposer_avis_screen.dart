import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/ferha_colors.dart';
import '../../core/theme/ferha_radii.dart';
import '../search/search_filters.dart';
import '../search/widgets/etats.dart';
import 'avis.dart';
import 'avis_messages.dart';
import 'avis_providers.dart';
import 'widgets/etoiles.dart';

/// Le champ de commentaire libre.
const Key cleCommentaireAvis = Key('avis-commentaire');

/// Le bouton qui publie — ou qui corrige.
const Key clePublierAvis = Key('avis-publier');

/// Déposer un avis, ou le corriger (§5.4 ; §4.2, CLI-08).
///
/// UN SEUL ÉCRAN POUR LES DEUX GESTES, parce que c'en est un seul vu du client :
/// il raconte sa soirée, et s'il revient dessus, il la raconte autrement. C'est
/// `deposer_avis()` (026) qui sait si elle insère ou si elle corrige, et l'écran
/// n'a qu'un bouton — dont seul le libellé change.
///
/// ON Y ENTRE PAR DEUX PORTES : le bouton de « Mes réservations », sur une
/// soirée honorée, et la notification « Racontez votre soirée » que
/// `complete_booking()` dépose. Les deux mènent ici, et nulle part ailleurs.
///
/// AUCUNE REDIRECTION NE LE PROTÈGE, comme l'écran 6 : `avis_a_deposer()` refuse
/// d'elle-même un appel sans session (FE074) et la réservation d'un autre
/// (FE075). L'écran traduit ses refus en une phrase et propose le geste qui
/// reste ; une `redirect` ferait un second gardien pour la même règle.
class DeposerAvisScreen extends ConsumerWidget {
  /// Crée l'écran de dépôt.
  const DeposerAvisScreen({required this.bookingId, super.key});

  /// La réservation notée — la ligne représentative de son groupe.
  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avis = ref.watch(avisADeposerProvider(bookingId));

    return Scaffold(
      appBar: AppBar(title: const Text('Votre avis')),
      body: switch (avis) {
        AsyncError(:final error) => _Refus(
          erreur: error,
          onReessayer: () => ref.invalidate(avisADeposerProvider(bookingId)),
        ),
        AsyncData(:final value) => _Formulaire(
          // LA CLÉ CHANGE QUAND L'AVIS NAÎT, et c'est voulu : le formulaire se
          // réamorce alors sur ce que la base a réellement enregistré, plutôt
          // que de garder l'état d'un écran qui n'était pas encore celui d'un
          // avis publié. Une correction, elle, garde la même clé et donc le
          // texte en cours de frappe.
          key: ValueKey<String?>(value.avisId),
          avis: value,
        ),
        _ => const _Squelette(),
      },
    );
  }
}

/// Un refus d'`avis_a_deposer()`, dit en une phrase.
///
/// PAS D'[EtatErreur] TEL QUEL : son bouton « Réessayer » est juste pour un
/// réseau tombé et faux pour « la fenêtre est passée », qui rendra la même
/// réponse à chaque appui. On lit donc [refusAvis], et le bouton ne s'affiche
/// que sur ce qui peut changer d'avis.
class _Refus extends StatelessWidget {
  const _Refus({required this.erreur, required this.onReessayer});

  final Object erreur;
  final VoidCallback onReessayer;

  @override
  Widget build(BuildContext context) {
    final refus = refusAvis(erreur);

    if (!refus.definitif) {
      return EtatErreur(
        titre: 'Votre avis n’a pas pu être ouvert',
        erreur: erreur,
        onReessayer: onReessayer,
      );
    }

    return EtatVide(
      icone: Icons.rate_review_outlined,
      titre: 'Cet avis ne peut pas être déposé',
      explication: refus.message,
    );
  }
}

class _Formulaire extends ConsumerStatefulWidget {
  const _Formulaire({required this.avis, super.key});

  final AvisADeposer avis;

  @override
  ConsumerState<_Formulaire> createState() => _FormulaireState();
}

class _FormulaireState extends ConsumerState<_Formulaire> {
  late final TextEditingController _commentaire;
  late int? _note;
  late Map<SousNote, int> _sousNotes;

  bool _enCours = false;
  String? _refus;

  @override
  void initState() {
    super.initState();
    _note = widget.avis.note;
    _sousNotes = Map<SousNote, int>.from(widget.avis.sousNotes);
    _commentaire = TextEditingController(text: widget.avis.commentaire ?? '');
  }

  @override
  void dispose() {
    _commentaire.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avis = widget.avis;
    final ouvert = avis.modifiable;

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 24),
            children: <Widget>[
              _RappelDeLaSoiree(avis: avis),

              if (!ouvert) ...<Widget>[
                const SizedBox(height: 16),
                _PourquoiCEstFige(avis: avis),
              ],

              const SizedBox(height: 24),
              Text(
                'Votre note',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                'Obligatoire, de 1 à 5 étoiles.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.ferhaColors.inkSecondary,
                ),
              ),
              const SizedBox(height: 6),
              ChoixEtoiles(
                cle: 'globale',
                libelleSemantique: 'Note globale',
                note: _note,
                taille: 34,
                onChoisir: ouvert
                    ? (n) => setState(() {
                        _note = n;
                        _refus = null;
                      })
                    : (_) {},
              ),

              const SizedBox(height: 22),
              Text(
                'Le détail, si vous voulez',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                // Le dire évite qu'on croie devoir remplir les quatre pour
                // pouvoir publier — et quatre notes données au jugé valent
                // moins que trois cases laissées vides.
                'Facultatif. Appuyez à nouveau sur une étoile allumée pour '
                'effacer une note.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.ferhaColors.inkSecondary,
                ),
              ),
              const SizedBox(height: 8),
              for (final sousNote in SousNote.values)
                _LigneSousNote(
                  sousNote: sousNote,
                  note: _sousNotes[sousNote],
                  actif: ouvert,
                  onChoisir: (n) => setState(() {
                    if (n == null) {
                      _sousNotes.remove(sousNote);
                    } else {
                      _sousNotes[sousNote] = n;
                    }
                  }),
                ),

              const SizedBox(height: 22),
              Text(
                'Racontez votre soirée',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextField(
                key: cleCommentaireAvis,
                controller: _commentaire,
                enabled: ouvert,
                maxLines: 6,
                maxLength: 1500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText:
                      'Ce qui vous a plu, ce qui vous a manqué. C’est ce que '
                      'liront les familles qui hésitent.',
                ),
              ),

              if (avis.reponse != null) ...<Widget>[
                const SizedBox(height: 12),
                _ReponseRecue(reponse: avis.reponse!),
              ],

              if (_refus != null) ...<Widget>[
                const SizedBox(height: 14),
                _MessageDeRefus(message: _refus!),
              ],
            ],
          ),
        ),

        if (ouvert)
          _BarreDePublication(
            dejaDepose: avis.dejaDepose,
            fermeLe: avis.fermeLe,
            enCours: _enCours,
            // « Publier » reste éteint sans note globale : la base la refuse
            // (FE079), et un bouton allumé qui mène à un refus est une promesse
            // non tenue.
            onPublier: _note == null || _enCours ? null : _publier,
          ),
      ],
    );
  }

  Future<void> _publier() async {
    setState(() {
      _enCours = true;
      _refus = null;
    });

    try {
      await ref
          .read(avisServiceProvider)
          .deposer(
            widget.avis,
            note: _note!,
            sousNotes: _sousNotes,
            // Le champ vide part en `null` : « pas de commentaire » et « un
            // commentaire vide » ne se rangent pas pareil, et c'est la base qui
            // détoure les espaces (026).
            commentaire: _commentaire.text.trim().isEmpty
                ? null
                : _commentaire.text,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.avis.dejaDepose
                ? 'Votre avis est à jour. Merci.'
                : 'Votre avis est publié. Merci d’avoir raconté votre soirée.',
          ),
        ),
      );
    } on Object catch (erreur) {
      if (!mounted) return;
      setState(() => _refus = messageErreurAvis(erreur));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }
}

/// La soirée dont on parle — salle, date, créneau, invités.
///
/// ELLE EST EN HAUT PARCE QU'ON NOTE PARFOIS DEUX SEMAINES APRÈS. Sans elle,
/// l'écran demanderait des étoiles sans dire pour quoi.
class _RappelDeLaSoiree extends StatelessWidget {
  const _RappelDeLaSoiree({required this.avis});

  final AvisADeposer avis;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: FerhaRadii.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            avis.salle,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            <String>[
              avis.localisation,
              '${dateEnFrancais(avis.date)}, '
                  '${avis.creneau.libelle.toLowerCase()}',
              '${avis.invites} invités',
            ].join(' · '),
            style: text.bodySmall?.copyWith(color: colors.inkSecondary),
          ),
        ],
      ),
    );
  }
}

/// Pourquoi l'écran est en lecture seule.
///
/// DEUX RAISONS, ET DEUX PHRASES. « Le propriétaire a répondu » et « les trente
/// jours sont passés » ne se répondent pas de la même façon, et la première
/// demande une justification : sans elle, la règle passe pour une brimade.
class _PourquoiCEstFige extends StatelessWidget {
  const _PourquoiCEstFige({required this.avis});

  final AvisADeposer avis;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    final phrase = avis.figeParLaReponse
        ? 'Le propriétaire a répondu à votre avis : il est maintenant figé. '
              'Une réponse publique sous un avis qu’on réécrirait ensuite ne '
              'voudrait plus rien dire.'
        : avis.fenetreOuverte
        ? 'Cet avis n’est plus modifiable.'
        : 'Les avis s’écrivent du ${dateEnFrancais(avis.ouvreLe)} au '
              '${dateEnFrancais(avis.fermeLe)}. Cette période est passée, '
              'votre avis reste publié tel quel.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: colors.goldSoft,
        borderRadius: FerhaRadii.cardBorder,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.lock_outline, size: 18, color: colors.primaryDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              phrase,
              style: text.bodySmall?.copyWith(color: colors.inkSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReponseRecue extends StatelessWidget {
  const _ReponseRecue({required this.reponse});

  final String reponse;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsetsDirectional.only(start: 10),
      decoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(color: colors.primary, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Réponse du propriétaire',
            style: text.labelSmall?.copyWith(
              color: colors.primaryDeep,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            reponse,
            style: text.bodySmall?.copyWith(
              color: colors.inkSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _LigneSousNote extends StatelessWidget {
  const _LigneSousNote({
    required this.sousNote,
    required this.note,
    required this.actif,
    required this.onChoisir,
  });

  final SousNote sousNote;
  final int? note;
  final bool actif;
  final ValueChanged<int?> onChoisir;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              sousNote.libelle,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.inkSecondary),
            ),
          ),
          ChoixEtoiles(
            cle: sousNote.name,
            libelleSemantique: sousNote.libelle,
            note: note,
            taille: 22,
            effacable: true,
            onChoisir: actif ? onChoisir : (_) {},
          ),
        ],
      ),
    );
  }
}

/// La barre du bas : le bouton, et jusqu'à quand il reste allumé.
class _BarreDePublication extends StatelessWidget {
  const _BarreDePublication({
    required this.dejaDepose,
    required this.fermeLe,
    required this.enCours,
    required this.onPublier,
  });

  final bool dejaDepose;
  final DateTime fermeLe;
  final bool enCours;
  final VoidCallback? onPublier;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: BorderDirectional(top: BorderSide(color: colors.ruleSoft)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                key: clePublierAvis,
                onPressed: onPublier,
                icon: enCours
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined, size: 18),
                label: Text(
                  dejaDepose ? 'Modifier mon avis' : 'Publier mon avis',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              // LA DATE LIMITE VIENT DE LA BASE (026), et elle est écrite ici
              // parce qu'un avis corrigeable est une chose qu'on oublie : le
              // propriétaire peut répondre demain, et la porte se ferme.
              dejaDepose
                  ? 'Modifiable jusqu’au ${dateEnFrancais(fermeLe)}, ou '
                        'jusqu’à la réponse du propriétaire.'
                  : 'À déposer avant le ${dateEnFrancais(fermeLe)}.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: colors.inkTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageDeRefus extends StatelessWidget {
  const _MessageDeRefus({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final rouge = Theme.of(context).colorScheme.error;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: FerhaRadii.cardBorder,
        border: Border.all(color: rouge),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 18, color: rouge),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.inkSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Squelette extends StatelessWidget {
  const _Squelette();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 24),
      children: <Widget>[
        for (final hauteur in <double>[72, 96, 140, 160])
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 16),
            child: Container(
              height: hauteur,
              decoration: BoxDecoration(
                color: colors.surfaceSecondary,
                borderRadius: FerhaRadii.cardBorder,
              ),
            ),
          ),
      ],
    );
  }
}
