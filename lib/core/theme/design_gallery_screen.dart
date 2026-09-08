import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/generated/app_localizations.dart';
import '../l10n/locale_controller.dart';
import '../supabase/supabase_providers.dart';
import 'ferha_colors.dart';
import 'ferha_radii.dart';

/// Galerie de contrôle de l'identité visuelle — route cachée `/_design`.
///
/// Elle n'affiche aucune donnée métier : uniquement les jetons du thème, pour
/// vérifier d'un coup d'œil que le clair et le sombre tiennent la route.
class DesignGalleryScreen extends ConsumerWidget {
  /// Crée la galerie de contrôle.
  const DesignGalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.ferhaColors;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.designGalleryTitle),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: TextButton.icon(
              onPressed: () => ref.read(localeProvider.notifier).toggle(),
              icon: const Icon(Icons.translate, size: 18),
              label: Text(l10n.switchLanguage),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 32),
        children: <Widget>[
          // TEMPORAIRE — retirer en J6
          const _Section(
            title: 'État de la connexion',
            subtitle: 'Vérification du branchement sur Supabase',
            child: _ConnexionCard(),
          ),
          _Section(
            title: 'Couleurs',
            subtitle: 'Palette « Ambre & ivoire », thème courant',
            child: _Swatches(colors: colors),
          ),
          _Section(
            title: 'Typographie',
            subtitle:
                'Bricolage Grotesque pour les titres, système pour le '
                'corps de texte',
            child: const _TypeScale(),
          ),
          _Section(title: 'Boutons', child: const _Buttons()),
          _Section(title: 'Puces', child: const _Chips()),
          _Section(
            title: 'Carte de salle',
            subtitle: 'Structure seule, sans données',
            child: const _EmptyVenueCard(),
          ),
          _Section(
            title: 'Calendrier',
            subtitle: 'Les trois états de disponibilité',
            child: const _CalendarStates(),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// TEMPORAIRE — retirer en J6
//
// Cet encart est un instrument de branchement, pas un écran. Il pose à la base
// la question la plus simple qui prouve que la chaîne complète fonctionne —
// clés, réseau, RLS, données de démonstration — et montre les trois états sans
// en cacher aucun.
//
// En cas d'erreur, il affiche le VRAI message. « Une erreur est survenue » ne
// dit ni que la clé est fausse, ni que la table est fermée, ni qu'il n'y a pas
// de réseau : ce sont trois gestes différents, et c'est le message d'origine
// qui les distingue.
//
// Il disparaît avec la galerie de contrôle dès qu'un écran métier lit ces
// mêmes données. Ni ce widget ni son fournisseur ne doivent servir ailleurs.
// -----------------------------------------------------------------------------

/// Ce que la base répond à la question « combien de salles publiées ? ».
typedef _EtatConnexion = ({int salles, String? premiere});

/// TEMPORAIRE — retirer en J6
final _connexionProvider = FutureProvider.autoDispose<_EtatConnexion>((
  ref,
) async {
  final client = ref.watch(supabaseClientProvider);

  // `count` porte sur toutes les lignes visibles, `limit(1)` ne ramène que la
  // première : on obtient le total sans télécharger le catalogue.
  //
  // Le filtre `status = 'published'` est une commodité d'affichage, pas une
  // sécurité : la politique venues_select_published_or_own (002) rend de toute
  // façon les brouillons d'autrui invisibles.
  final reponse = await client
      .from('venues')
      .select('name')
      .eq('status', 'published')
      .order('name')
      .limit(1)
      .count(CountOption.exact);

  final lignes = reponse.data;
  return (
    salles: reponse.count,
    premiere: lignes.isEmpty ? null : lignes.first['name'] as String?,
  );
});

/// TEMPORAIRE — retirer en J6
class _ConnexionCard extends ConsumerWidget {
  const _ConnexionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etat = ref.watch(_connexionProvider);

    return etat.when(
      loading: () => const _ConnexionLigne(
        icone: Icons.hourglass_empty,
        titre: 'Interrogation de la base…',
      ),
      error: (erreur, _) => _ConnexionLigne(
        icone: Icons.cloud_off_outlined,
        titre: 'La base n’a pas répondu',
        // Le message d'origine, tel quel. C'est lui qui dit quoi faire.
        detail: erreur.toString(),
        estErreur: true,
        onReessayer: () => ref.invalidate(_connexionProvider),
      ),
      data: (donnees) => _ConnexionLigne(
        icone: Icons.cloud_done_outlined,
        titre: donnees.salles == 0
            ? 'Connecté — aucune salle publiée'
            : '${donnees.salles} salle${donnees.salles > 1 ? 's' : ''} '
                  'publiée${donnees.salles > 1 ? 's' : ''}',
        detail: donnees.premiere == null
            ? 'La base répond, mais le catalogue est vide. '
                  'Lancez supabase/seed/001_demo_venues.sql.'
            : 'Première par ordre alphabétique : ${donnees.premiere}',
        onReessayer: () => ref.invalidate(_connexionProvider),
      ),
    );
  }
}

/// TEMPORAIRE — retirer en J6
class _ConnexionLigne extends StatelessWidget {
  const _ConnexionLigne({
    required this.icone,
    required this.titre,
    this.detail,
    this.estErreur = false,
    this.onReessayer,
  });

  final IconData icone;
  final String titre;
  final String? detail;
  final bool estErreur;
  final VoidCallback? onReessayer;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    // Les couleurs de créneau (slotFree, slotBooked) sont réservées au
    // calendrier : on prend celle du thème pour l'erreur, et l'ambre pour le
    // reste.
    final accent = estErreur
        ? Theme.of(context).colorScheme.error
        : colors.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: FerhaRadii.cardBorder,
        border: Border.all(color: estErreur ? accent : colors.rule),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 2, end: 12),
            child: Icon(icone, size: 20, color: accent),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  titre,
                  style: text.titleSmall?.copyWith(color: colors.ink),
                ),
                if (detail != null) ...<Widget>[
                  const SizedBox(height: 6),
                  SelectableText(
                    detail!,
                    style: text.bodySmall?.copyWith(
                      color: colors.inkSecondary,
                      fontFamily: estErreur ? 'monospace' : null,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onReessayer != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: IconButton(
                onPressed: onReessayer,
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Réessayer',
              ),
            ),
        ],
      ),
    );
  }
}

/// Formate une couleur en notation hexadécimale RVB.
String _hex(Color color) {
  final argb = color.toARGB32();
  return '#${argb.toRadixString(16).toUpperCase().padLeft(8, '0').substring(2)}';
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: text.titleLarge),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: text.bodySmall?.copyWith(color: colors.inkSecondary),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches({required this.colors});

  final FerhaColors colors;

  @override
  Widget build(BuildContext context) {
    final entries = <({String label, Color color, String usage})>[
      (
        label: 'Principale',
        color: colors.primary,
        usage: 'Boutons, onglet actif',
      ),
      (
        label: 'Principale foncée',
        color: colors.primaryDeep,
        usage: 'Prix, liens',
      ),
      (label: 'Principale douce', color: colors.primarySoft, usage: 'Encarts'),
      (
        label: 'Encre sur principale',
        color: colors.onPrimary,
        usage: 'Texte des boutons',
      ),
      (
        label: 'Fond — ivoire',
        color: colors.background,
        usage: 'Toutes les pages',
      ),
      (label: 'Surface', color: colors.surface, usage: 'Cartes, feuilles'),
      (
        label: 'Surface secondaire',
        color: colors.surfaceSecondary,
        usage: 'Champs, puces',
      ),
      (
        label: 'Accent — rose poudré',
        color: colors.rose,
        usage: 'Puces, conseils',
      ),
      (label: 'Rose doux', color: colors.roseSoft, usage: 'Fond de conseil'),
      (
        label: 'Encre rose',
        color: colors.roseInk,
        usage: 'Texte sur rose doux',
      ),
      (label: 'Or', color: colors.gold, usage: 'Étoiles, et rien d’autre'),
      (label: 'Or doux', color: colors.goldSoft, usage: 'Fond de note'),
      (label: 'Texte', color: colors.ink, usage: 'Encre principale'),
      (
        label: 'Texte secondaire',
        color: colors.inkSecondary,
        usage: 'Descriptions',
      ),
      (label: 'Texte tertiaire', color: colors.inkTertiary, usage: 'Légendes'),
      (label: 'Filets', color: colors.rule, usage: 'Bordures'),
      (
        label: 'Filets doux',
        color: colors.ruleSoft,
        usage: 'Séparateurs internes',
      ),
      (label: 'Libre — sauge', color: colors.slotFree, usage: 'Calendrier'),
      (label: 'Libre, fond', color: colors.slotFreeSoft, usage: 'Calendrier'),
      (
        label: 'Réservé — terracotta',
        color: colors.slotBooked,
        usage: 'Calendrier',
      ),
      (
        label: 'Réservé, fond',
        color: colors.slotBookedSoft,
        usage: 'Calendrier',
      ),
      (
        label: 'Indisponible',
        color: colors.slotUnavailable,
        usage: 'Calendrier',
      ),
      (
        label: 'Indisponible, fond',
        color: colors.slotUnavailableSoft,
        usage: 'Calendrier',
      ),
    ];

    return Column(
      children: <Widget>[
        for (final entry in entries)
          _SwatchRow(
            label: entry.label,
            color: entry.color,
            usage: entry.usage,
          ),
      ],
    );
  }
}

class _SwatchRow extends StatelessWidget {
  const _SwatchRow({
    required this.label,
    required this.color,
    required this.usage,
  });

  final String label;
  final Color color;
  final String usage;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: FerhaRadii.imageBorder,
              border: Border.all(color: colors.rule),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: text.titleSmall),
                Text(
                  usage,
                  style: text.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _hex(color),
            style: text.bodySmall?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              color: colors.inkSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeScale extends StatelessWidget {
  const _TypeScale();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final samples = <(String, TextStyle?)>[
      ('displayLarge', text.displayLarge),
      ('displayMedium', text.displayMedium),
      ('displaySmall', text.displaySmall),
      ('headlineLarge', text.headlineLarge),
      ('headlineMedium', text.headlineMedium),
      ('headlineSmall', text.headlineSmall),
      ('titleLarge', text.titleLarge),
      ('titleMedium', text.titleMedium),
      ('titleSmall', text.titleSmall),
      ('bodyLarge', text.bodyLarge),
      ('bodyMedium', text.bodyMedium),
      ('bodySmall', text.bodySmall),
      ('labelLarge', text.labelLarge),
      ('labelMedium', text.labelMedium),
      ('labelSmall', text.labelSmall),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final (name, style) in samples)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$name · ${style?.fontSize?.toStringAsFixed(0) ?? '?'} px',
                  style: text.labelSmall,
                ),
                Text('Salle des fêtes · 250 invités', style: style),
              ],
            ),
          ),
      ],
    );
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: <Widget>[
        FilledButton(onPressed: () {}, child: const Text('Bouton principal')),
        OutlinedButton(
          onPressed: () {},
          child: const Text('Bouton secondaire'),
        ),
        TextButton(onPressed: () {}, child: const Text('Bouton texte')),
        const FilledButton(onPressed: null, child: Text('Bouton désactivé')),
      ],
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        const Chip(label: Text('Neutre')),
        ChoiceChip(
          label: const Text('Sélectionnée'),
          selected: true,
          onSelected: (_) {},
        ),
        ChoiceChip(
          label: const Text('Non sélectionnée'),
          selected: false,
          onSelected: (_) {},
        ),
        Chip(
          label: const Text('Équipement'),
          backgroundColor: colors.roseSoft,
          side: BorderSide(color: colors.rose),
          labelStyle: TextStyle(color: colors.roseInk, fontSize: 13),
        ),
        Chip(
          avatar: Icon(Icons.star, size: 16, color: colors.gold),
          label: const Text('4,6'),
          backgroundColor: colors.goldSoft,
          side: BorderSide(color: colors.gold),
        ),
      ],
    );
  }
}

class _EmptyVenueCard extends StatelessWidget {
  const _EmptyVenueCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 140,
            color: colors.surfaceSecondary,
            alignment: AlignmentDirectional.center,
            child: Icon(
              Icons.image_outlined,
              size: 32,
              color: colors.inkTertiary,
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: <Widget>[
                _Bar(width: 160, height: 14, color: colors.surfaceSecondary),
                _Bar(width: 110, height: 10, color: colors.ruleSoft),
                Row(
                  children: <Widget>[
                    _Bar(width: 70, height: 12, color: colors.surfaceSecondary),
                    const Spacer(),
                    _Bar(width: 46, height: 12, color: colors.surfaceSecondary),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height, required this.color});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: FerhaRadii.chipBorder,
      ),
    );
  }
}

class _CalendarStates extends StatelessWidget {
  const _CalendarStates();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Row(
      spacing: 10,
      children: <Widget>[
        Expanded(
          child: _CalendarDay(
            day: '12',
            label: 'Libre',
            background: colors.slotFreeSoft,
            foreground: colors.slotFree,
          ),
        ),
        Expanded(
          child: _CalendarDay(
            day: '13',
            label: 'Réservé',
            background: colors.slotBookedSoft,
            foreground: colors.slotBooked,
          ),
        ),
        Expanded(
          child: _CalendarDay(
            day: '14',
            label: 'Indisponible',
            background: colors.slotUnavailableSoft,
            foreground: colors.slotUnavailable,
          ),
        ),
      ],
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.day,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String day;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      children: <Widget>[
        Container(
          height: 56,
          alignment: AlignmentDirectional.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: FerhaRadii.imageBorder,
            border: Border.all(color: foreground),
          ),
          child: Text(
            day,
            style: text.titleMedium?.copyWith(color: foreground),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: text.labelSmall, textAlign: TextAlign.center),
      ],
    );
  }
}
