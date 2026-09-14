import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/direction_du_texte.dart';
import '../../core/theme/ferha_colors.dart';
import '../../core/theme/ferha_radii.dart';
import '../owner/owner_providers.dart';
import '../search/widgets/etats.dart';
import 'avis.dart';
import 'avis_messages.dart';
import 'avis_providers.dart';
import 'widgets/etoiles.dart';

/// Le bouton « Répondre » d'un avis donné, côté propriétaire.
Key cleRepondreAvis(String avisId) => Key('avis-repondre-$avisId');

/// Le champ de la fenêtre de réponse.
const Key cleChampReponse = Key('avis-reponse-champ');

/// Le bouton qui publie la réponse.
const Key cleEnvoyerReponse = Key('avis-reponse-envoyer');

/// Les avis d'une salle — l'écran 7 des maquettes.
///
/// IL EST PUBLIC, et c'est le point : un avis sert d'abord à celui qui n'a pas
/// encore réservé (§3, étape 2). Aucune redirection ne le protège, et
/// `avis_de_la_salle()` (026) est ouverte à `anon`.
///
/// LE BLOC « ✦ Synthèse des 34 avis » N'EXISTE QUE QUAND ELLE EXISTE. Il est
/// pré-calculé la nuit par « summarize-reviews » (§8.2), et il manque dans deux
/// cas : la salle a moins de trois avis porteurs de texte — on ne résume pas
/// deux phrases —, ou la nuit n'est pas encore passée dessus. L'écran ne dessine
/// alors rien du tout : un cadre vide dirait au visiteur que l'application est
/// inachevée, plus fort que son absence.
///
/// CE QU'IL AFFICHE ET QUE LA MAQUETTE NE DESSINE PAS : « Répondre », sur les
/// avis d'une salle dont le lecteur est le propriétaire (§4.3, OWN-06). La
/// maquette de l'écran 9 dessine une réponse déjà posée, jamais le geste qui la
/// pose — et il fallait bien qu'il vive quelque part. Ici, plutôt que dans un
/// écran propriétaire de plus : c'est la MÊME liste, lue par quelqu'un d'autre,
/// et une seconde liste finirait par diverger de celle-ci.
class AvisScreen extends ConsumerWidget {
  /// Crée l'écran des avis d'une salle.
  const AvisScreen({required this.venueId, super.key});

  /// La salle dont on lit les avis.
  final String venueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avis = ref.watch(avisDeLaSalleProvider(venueId));

    return Scaffold(
      appBar: AppBar(
        title: Text(switch (avis) {
          // « Avis · 34 », comme la maquette. Le compte n'apparaît qu'une fois
          // connu : « Avis · 0 » pendant le chargement se lirait comme une
          // réponse, et ce n'en est pas une.
          AsyncData(:final value) when value.nombre > 0 =>
            'Avis · ${value.nombre}',
          _ => 'Avis',
        }),
      ),
      body: switch (avis) {
        AsyncError(:final error) => EtatErreur(
          titre: 'Les avis n’ont pas pu être chargés',
          erreur: error,
          onReessayer: () => ref.invalidate(avisDeLaSalleProvider(venueId)),
        ),
        AsyncData(:final value) => _Contenu(salle: value),
        _ => const _Squelette(),
      },
    );
  }
}

class _Contenu extends ConsumerWidget {
  const _Contenu({required this.salle});

  final AvisDeLaSalle salle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!salle.estNotee) {
      // Une salle neuve n'est pas une salle mal notée. On ne montre ni « 0,0 »
      // ni des étoiles vides : on dit qu'il n'y a rien à lire, et pourquoi.
      return EtatVide(
        icone: Icons.rate_review_outlined,
        titre: 'Aucun avis pour l’instant',
        explication:
            'Les avis de ${salle.salle} s’afficheront ici. Seules les '
            'familles qui ont réellement réservé peuvent en déposer.',
      );
    }

    // Le propriétaire de la salle voit un bouton de plus sur chaque avis sans
    // réponse. C'est une question d'AFFICHAGE, pas un droit : c'est
    // `repondre_a_un_avis()` (026) qui refuse la salle d'un autre.
    final estMaSalle = ref.watch(estMaSalleProvider(salle.venueId));

    return RefreshIndicator(
      onRefresh: () async =>
          ref.invalidate(avisDeLaSalleProvider(salle.venueId)),
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 28),
        children: <Widget>[
          _EnTeteDesNotes(salle: salle),

          // Entre les notes et la liste, comme sur la maquette : on lit
          // d'abord le chiffre, puis ce qu'il veut dire, puis les avis eux-mêmes.
          if (salle.synthese != null) ...<Widget>[
            const SizedBox(height: 14),
            _BlocSynthese(synthese: salle.synthese!),
          ],

          const SizedBox(height: 20),
          for (final avis in salle.avis) ...<Widget>[
            _CarteAvis(
              salle: salle,
              avis: avis,
              peutRepondre: estMaSalle && !avis.aUneReponse,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// La note globale, ses étoiles, et les quatre sous-notes en barres.
///
/// TOUT VIENT DE `venue_ratings` (§5.4). Rien ici ne fait de moyenne : ni la
/// globale, qui est bayésienne, ni les quatre autres, qui sont de simples
/// moyennes des sous-notes renseignées. Les recalculer en Dart donnerait une
/// seconde définition de la note affichée — et c'est exactement ce que le
/// cahier des charges interdit pour le prix.
class _EnTeteDesNotes extends StatelessWidget {
  const _EnTeteDesNotes({required this.salle});

  final AvisDeLaSalle salle;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final note = salle.note!;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              note.toStringAsFixed(1).replaceAll('.', ','),
              style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            RangeeEtoiles(note: note, taille: 15),
            const SizedBox(height: 2),
            Text(
              '${salle.nombre} avis',
              style: text.bodySmall?.copyWith(color: colors.inkTertiary),
            ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Une sous-note que personne n'a remplie n'a pas de barre. Une
              // barre à zéro se lirait « 0 sur 5 » — c'est-à-dire le contraire
              // de « on ne sait pas ».
              for (final sousNote in SousNote.values)
                if (salle.moyennes[sousNote] != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: 4),
                    child: BarreSousNote(
                      libelle: sousNote.libelle,
                      note: salle.moyennes[sousNote]!,
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Le bloc « ✦ Synthèse des N avis », et sa date.
///
/// TROIS CHOSES S'Y LISENT, ET LA TROISIÈME EST LA PLUS IMPORTANTE :
///
///   * que c'est un résumé, et non un avis de plus — d'où l'étiquette ;
///   * de combien d'avis il vient — celui d'ALORS, pas celui d'aujourd'hui ;
///   * de QUAND il date. Un résumé sans date se lirait comme une vérité
///     permanente ; avec sa date, le lecteur sait qu'un avis déposé depuis n'y
///     est pas encore.
///
/// AUCUNE MENTION « ÉCRIT PAR UNE IA », et ce n'est pas un oubli. L'étiquette
/// dit « Synthèse des N avis » : elle dit d'où vient le texte — des avis, tous
/// vérifiés —, ce qui est l'information dont dépend la confiance. Comment la
/// phrase a été assemblée intéresse moins que sur quoi elle porte.
///
/// LE TEXTE EST DANS LA LANGUE DES AVIS, pas dans celle de l'application : la
/// synthèse d'avis arabes est en arabe, et elle se lit de droite à gauche même
/// dans une application en français. Les avis qu'elle résume sont juste en
/// dessous, dans la même langue.
class _BlocSynthese extends StatelessWidget {
  const _BlocSynthese({required this.synthese});

  final SyntheseDesAvis synthese;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(13),
      decoration: BoxDecoration(
        color: colors.primarySoft,
        borderRadius: FerhaRadii.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.auto_awesome, size: 13, color: colors.primaryDeep),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Synthèse des ${synthese.nombre} avis',
                  style: text.labelSmall?.copyWith(
                    color: colors.primaryDeep,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Text(
                synthese.moisDeMiseAJour,
                style: text.labelSmall?.copyWith(color: colors.primaryDeep),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TexteDansSaLangue(
            synthese.texte,
            style: text.bodySmall?.copyWith(
              color: colors.inkSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Un avis, sa pastille, sa note, son texte — et la réponse du propriétaire.
class _CarteAvis extends ConsumerStatefulWidget {
  const _CarteAvis({
    required this.salle,
    required this.avis,
    required this.peutRepondre,
  });

  final AvisDeLaSalle salle;
  final AvisPublie avis;
  final bool peutRepondre;

  @override
  ConsumerState<_CarteAvis> createState() => _CarteAvisState();
}

class _CarteAvisState extends ConsumerState<_CarteAvis> {
  bool _enCours = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final avis = widget.avis;

    return Container(
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: FerhaRadii.cardBorder,
        border: Border.all(color: colors.ruleSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _Pastille(initiales: avis.initiales),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // « Amina H. » — le nom arrive déjà raccourci de la base, et
                    // c'est la seule forme dans laquelle il en sort (§9).
                    Text(
                      avis.auteur,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    RangeeEtoiles(note: avis.note.toDouble(), taille: 13),
                  ],
                ),
              ),
              Text(
                avis.moisDePublication,
                style: text.bodySmall?.copyWith(color: colors.inkTertiary),
              ),
            ],
          ),

          if (avis.commentaire != null && avis.commentaire!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              avis.commentaire!,
              style: text.bodyMedium?.copyWith(
                color: colors.inkSecondary,
                height: 1.45,
              ),
            ),
          ],

          if (avis.sousNotes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final entree in avis.sousNotes.entries)
                  _PuceSousNote(
                    libelle: entree.key.libelle,
                    note: entree.value,
                  ),
              ],
            ),
          ],

          const SizedBox(height: 10),
          const _ReservationVerifiee(),

          if (avis.reponse != null) ...<Widget>[
            const SizedBox(height: 12),
            _ReponseDuProprietaire(reponse: avis.reponse!),
          ],

          if (widget.peutRepondre) ...<Widget>[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                key: cleRepondreAvis(avis.id),
                onPressed: _enCours ? null : _repondre,
                icon: const Icon(Icons.reply_outlined, size: 18),
                label: const Text('Répondre'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Une réponse se publie UNE FOIS et ne se réécrit pas (§4.3, OWN-06). La
  /// fenêtre le dit avant d'envoyer, plutôt qu'après : c'est le genre de règle
  /// qu'on préfère apprendre en écrivant qu'en relisant.
  Future<void> _repondre() async {
    final reponse = await showDialog<String>(
      context: context,
      builder: (context) => _FenetreDeReponse(auteur: widget.avis.auteur),
    );

    if (reponse == null || !mounted) return;

    setState(() => _enCours = true);
    try {
      await ref
          .read(avisServiceProvider)
          .repondre(widget.salle, widget.avis, reponse);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Votre réponse est publiée.')),
      );
    } on Object catch (erreur) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(messageErreurReponseAvis(erreur))));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }
}

class _FenetreDeReponse extends StatefulWidget {
  const _FenetreDeReponse({required this.auteur});

  final String auteur;

  @override
  State<_FenetreDeReponse> createState() => _FenetreDeReponseState();
}

class _FenetreDeReponseState extends State<_FenetreDeReponse> {
  final TextEditingController _controleur = TextEditingController();

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Répondre à cet avis'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Votre réponse sera publique, sous l’avis de ${widget.auteur}. '
            'Vous ne pourrez pas la modifier ensuite, et l’avis ne pourra plus '
            'être réécrit non plus.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          TextField(
            key: cleChampReponse,
            controller: _controleur,
            autofocus: true,
            maxLines: 4,
            maxLength: 600,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Merci pour votre visite…',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Pas maintenant'),
        ),
        FilledButton(
          key: cleEnvoyerReponse,
          // Éteint sur une réponse vide : la base la refuse (FE083), et un
          // bouton allumé qui mène à un refus est une promesse non tenue.
          onPressed: _controleur.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_controleur.text.trim()),
          child: const Text('Publier la réponse'),
        ),
      ],
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({required this.initiales});

  final String initiales;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primarySoft,
        shape: BoxShape.circle,
      ),
      child: Text(
        initiales,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colors.primaryDeep,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// « ✓ Réservation vérifiée » — la phrase qui porte toute la règle du §5.4.
///
/// Elle est sur CHAQUE avis, et non sur certains : il n'existe pas d'avis non
/// vérifié dans Ferha, puisqu'un avis exige une réservation honorée. Le dire à
/// chaque fois est le seul moyen que le lecteur le sache.
class _ReservationVerifiee extends StatelessWidget {
  const _ReservationVerifiee();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: colors.slotFreeSoft,
        borderRadius: FerhaRadii.chipBorder,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.verified_outlined, size: 13, color: colors.slotFree),
          const SizedBox(width: 5),
          Text(
            'Réservation vérifiée',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.slotFree,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReponseDuProprietaire extends StatelessWidget {
  const _ReponseDuProprietaire({required this.reponse});

  final String reponse;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Container(
      // Un filet du côté du DÉBUT de ligne, pas à gauche : en arabe, la citation
      // se marque à droite.
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

class _PuceSousNote extends StatelessWidget {
  const _PuceSousNote({required this.libelle, required this.note});

  final String libelle;
  final int note;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 9,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: FerhaRadii.chipBorder,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            libelle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.inkSecondary),
          ),
          const SizedBox(width: 5),
          Icon(Icons.star_rounded, size: 12, color: colors.gold),
          const SizedBox(width: 2),
          Text(
            '$note',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
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
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 28),
      children: <Widget>[
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 12),
            child: Container(
              height: i == 0 ? 78 : 108,
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
