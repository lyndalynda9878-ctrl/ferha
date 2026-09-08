import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/ferha_colors.dart';
import 'search_filters.dart';
import 'search_providers.dart';
import 'widgets/etats.dart';
import 'widgets/venue_card.dart';

/// Écran 2 des maquettes — les résultats.
///
/// « Les filtres actifs restent visibles en tête. Le prix affiché est déjà
/// calculé pour la date choisie, majorations comprises — pas un "à partir
/// de". »
///
/// Les deux tiennent parce que rien n'est décidé ici : `search_venues()` filtre
/// et tarife, cet écran affiche. Retirer une puce ne fait pas de tri local — la
/// recherche repart, et le prix avec elle, puisqu'il dépend de la date.
///
/// Comme l'accueil, il ne demande aucune connexion.
class ResultatsScreen extends ConsumerWidget {
  /// Crée l'écran de résultats.
  const ResultatsScreen({required this.filtres, super.key});

  /// Les critères, relus depuis l'URL.
  final SearchFilters filtres;

  void _remplacer(BuildContext context, SearchFilters nouveaux) {
    context.replace(
      Uri(
        path: GoRouterState.of(context).uri.path,
        queryParameters: nouveaux.versParametres(),
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultat = ref.watch(resultatsProvider(filtres));
    final wilayas = ref.watch(wilayasProvider).value;
    final nomWilaya = filtres.wilayaCode == null
        ? null
        : wilayas
              ?.where((w) => w.code == filtres.wilayaCode)
              .map((w) => w.nom)
              .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          resultat.when(
            loading: () => 'Recherche…',
            error: (_, _) => 'Résultats',
            data: (d) => _titre(d.total, nomWilaya),
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          _FiltresActifs(
            filtres: filtres,
            nomWilaya: nomWilaya,
            onChanger: (nouveaux) => _remplacer(context, nouveaux),
          ),
          Expanded(
            child: resultat.when(
              loading: () => ListView.separated(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 32),
                itemCount: 3,
                separatorBuilder: (_, _) => const SizedBox(height: 16),
                itemBuilder: (_, _) => const CarteSquelette(),
              ),
              error: (erreur, _) => EtatErreur(
                erreur: erreur,
                onReessayer: () => ref.invalidate(resultatsProvider(filtres)),
              ),
              data: (donnees) {
                if (donnees.salles.isEmpty) {
                  return _Vide(
                    filtres: filtres,
                    nomWilaya: nomWilaya,
                    onChanger: (nouveaux) => _remplacer(context, nouveaux),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 32),
                  itemCount: donnees.salles.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (_, i) => VenueCard(salle: donnees.salles[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _titre(int total, String? wilaya) {
  final salles = total <= 1 ? '$total salle' : '$total salles';
  return wilaya == null ? salles : '$salles à $wilaya';
}

/// Les filtres actifs, en tête et toujours visibles.
///
/// Chaque puce se retire d'un tap. C'est la sortie de secours d'une recherche
/// trop étroite : on voit ce qui restreint, et on l'enlève sans revenir en
/// arrière.
class _FiltresActifs extends StatelessWidget {
  const _FiltresActifs({
    required this.filtres,
    required this.nomWilaya,
    required this.onChanger,
  });

  final SearchFilters filtres;
  final String? nomWilaya;
  final ValueChanged<SearchFilters> onChanger;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    final puces = <Widget>[
      if (filtres.date != null)
        _Puce(
          libelle:
              '${dateCourteEnFrancais(filtres.date!)} · '
              '${filtres.creneau.libelle.toLowerCase()}',
          onRetirer: () =>
              onChanger(filtres.copyWith(effacer: const <String>{'date'})),
        ),
      if (filtres.invites != null)
        _Puce(
          libelle: '${filtres.invites}+ couverts',
          onRetirer: () =>
              onChanger(filtres.copyWith(effacer: const <String>{'invites'})),
        ),
      if (nomWilaya != null)
        _Puce(
          libelle: nomWilaya!,
          onRetirer: () =>
              onChanger(filtres.copyWith(effacer: const <String>{'wilaya'})),
        ),
      if (filtres.budgetMax != null)
        _Puce(
          libelle: '≤ ${montantEnDinars(filtres.budgetMax!)} DA',
          onRetirer: () =>
              onChanger(filtres.copyWith(effacer: const <String>{'budget'})),
        ),
      if (filtres.typeEvenement != null)
        _Puce(
          libelle: filtres.typeEvenement!,
          onRetirer: () =>
              onChanger(filtres.copyWith(effacer: const <String>{'type'})),
        ),
      if (filtres.texte != null)
        _Puce(
          libelle: '« ${filtres.texte} »',
          onRetirer: () =>
              onChanger(filtres.copyWith(effacer: const <String>{'texte'})),
        ),
      for (final code in filtres.equipements)
        _Puce(
          libelle: code,
          onRetirer: () => onChanger(
            filtres.copyWith(
              equipements: filtres.equipements
                  .where((e) => e != code)
                  .toList(growable: false),
            ),
          ),
        ),
    ];

    if (puces.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.ruleSoft)),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: puces),
    );
  }
}

class _Puce extends StatelessWidget {
  const _Puce({required this.libelle, required this.onRetirer});

  final String libelle;
  final VoidCallback onRetirer;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return InputChip(
      label: Text(libelle),
      onDeleted: onRetirer,
      deleteIcon: const Icon(Icons.close, size: 16),
      deleteButtonTooltipMessage: 'Retirer ce filtre',
      backgroundColor: colors.primarySoft,
      side: BorderSide.none,
      labelStyle: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(color: colors.primaryDeep),
    );
  }
}

/// Résultat vide — avec de quoi s'en sortir.
///
/// Le texte nomme le critère le plus probablement responsable, et chaque piste
/// est un bouton qui le retire vraiment. Dire « aucun résultat » et s'arrêter
/// là laisse le client sans savoir si l'application est cassée.
class _Vide extends StatelessWidget {
  const _Vide({
    required this.filtres,
    required this.nomWilaya,
    required this.onChanger,
  });

  final SearchFilters filtres;
  final String? nomWilaya;
  final ValueChanged<SearchFilters> onChanger;

  @override
  Widget build(BuildContext context) {
    final pistes = <Widget>[
      if (filtres.date != null)
        OutlinedButton.icon(
          onPressed: () =>
              onChanger(filtres.copyWith(effacer: const <String>{'date'})),
          icon: const Icon(Icons.event_busy_outlined, size: 18),
          label: const Text('Chercher sans date'),
        ),
      if (filtres.invites != null)
        OutlinedButton.icon(
          onPressed: () =>
              onChanger(filtres.copyWith(effacer: const <String>{'invites'})),
          icon: const Icon(Icons.group_off_outlined, size: 18),
          label: Text('Sans le seuil de ${filtres.invites} couverts'),
        ),
      if (filtres.budgetMax != null)
        OutlinedButton.icon(
          onPressed: () =>
              onChanger(filtres.copyWith(effacer: const <String>{'budget'})),
          icon: const Icon(Icons.payments_outlined, size: 18),
          label: const Text('Sans limite de budget'),
        ),
      if (filtres.wilayaCode != null)
        OutlinedButton.icon(
          onPressed: () =>
              onChanger(filtres.copyWith(effacer: const <String>{'wilaya'})),
          icon: const Icon(Icons.public, size: 18),
          label: const Text('Toutes les wilayas'),
        ),
      if (filtres.equipements.isNotEmpty)
        OutlinedButton.icon(
          onPressed: () =>
              onChanger(filtres.copyWith(equipements: const <String>[])),
          icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
          label: const Text('Sans les équipements'),
        ),
      if (filtres.texte != null)
        OutlinedButton.icon(
          onPressed: () =>
              onChanger(filtres.copyWith(effacer: const <String>{'texte'})),
          icon: const Icon(Icons.search_off, size: 18),
          label: const Text('Sans le texte cherché'),
        ),
    ];

    return EtatVide(
      titre: 'Aucune salle ne réunit tous ces critères',
      explication: _explication(),
      pistes: pistes.isEmpty
          ? <Widget>[
              OutlinedButton.icon(
                onPressed: () => onChanger(const SearchFilters()),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Repartir de zéro'),
              ),
            ]
          : pistes,
    );
  }

  String _explication() {
    // On nomme le critère le plus souvent responsable, du plus restrictif au
    // moins : une date prise élimine tout, un budget bas presque tout.
    if (filtres.date != null) {
      return 'Le ${dateEnFrancais(filtres.date!)} au '
          '${filtres.creneau.libelle.toLowerCase()}, les salles restantes sont '
          'peut-être déjà réservées. Essayez une autre date, ou retirez-la '
          'pour voir tout le catalogue.';
    }
    if (filtres.budgetMax != null) {
      return 'Le budget est comparé au prix réel de la date, majorations '
          'comprises — il monte vite un vendredi d’été. Essayez sans limite '
          'pour voir les montants.';
    }
    if (filtres.invites != null) {
      return 'Aucune salle n’atteint ${filtres.invites} couverts avec ces '
          'critères. Un chiffre plus bas ouvrira le catalogue.';
    }
    if (nomWilaya != null) {
      return 'Rien ne correspond à $nomWilaya. Le catalogue ne couvre pas '
          'encore toutes les wilayas.';
    }
    return 'Retirez un critère pour élargir la recherche.';
  }
}
