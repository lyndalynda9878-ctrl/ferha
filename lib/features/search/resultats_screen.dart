import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/formats_ferha.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/router/routes.dart';
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
    final textes = AppLocalizations.of(context);
    final resultat = ref.watch(resultatsProvider(filtres));
    final wilayas = ref.watch(wilayasProvider).value;
    // Une puce montre un libellé, jamais un code : « Mariage », pas « mariage ».
    final types = ref.watch(typesEvenementProvider).value;
    final libelleType = filtres.typeEvenement == null
        ? null
        : types
                  ?.where((t) => t.code == filtres.typeEvenement)
                  .map((t) => t.libelle)
                  .firstOrNull ??
              filtres.typeEvenement;
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
            loading: () => textes.resultatsRecherche,
            error: (_, _) => textes.resultatsTitre,
            data: (d) => _titre(textes, d.total, nomWilaya),
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          _FiltresActifs(
            filtres: filtres,
            nomWilaya: nomWilaya,
            libelleType: libelleType,
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
                  itemBuilder: (_, i) => VenueCard(
                    salle: donnees.salles[i],
                    onTap: () => context.push(
                      Uri(
                        path: FerhaRoutes.salleDe(donnees.salles[i].id),
                        queryParameters: filtres.versParametres(),
                      ).toString(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _titre(AppLocalizations textes, int total, String? wilaya) {
  final salles = textes.resultatsSalles(total);
  return wilaya == null ? salles : textes.resultatsSallesA(salles, wilaya);
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
    required this.libelleType,
    required this.onChanger,
  });

  final SearchFilters filtres;
  final String? nomWilaya;
  final String? libelleType;
  final ValueChanged<SearchFilters> onChanger;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final textes = AppLocalizations.of(context);
    final formats = FormatsFerha(textes);

    final puces = <Widget>[
      if (filtres.date != null)
        _Puce(
          libelle: textes.puceDateCreneau(
            formats.dateCourte(filtres.date!),
            filtres.creneau.auMilieuDUnePhrase(textes),
          ),
          onRetirer: () =>
              onChanger(filtres.copyWith(effacer: const <String>{'date'})),
        ),
      if (filtres.invites != null)
        _Puce(
          libelle: textes.puceInvites('${filtres.invites}'),
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
          libelle: textes.puceBudget(formats.montant(filtres.budgetMax!)),
          onRetirer: () =>
              onChanger(filtres.copyWith(effacer: const <String>{'budget'})),
        ),
      if (libelleType != null)
        _Puce(
          libelle: libelleType!,
          onRetirer: () =>
              onChanger(filtres.copyWith(effacer: const <String>{'type'})),
        ),
      if (filtres.texte != null)
        _Puce(
          libelle: textes.puceTexte(filtres.texte!),
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
      deleteButtonTooltipMessage: AppLocalizations.of(context).retirerFiltre,
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
    final textes = AppLocalizations.of(context);
    final formats = FormatsFerha(textes);

    final pistes = <Widget>[
      if (filtres.date != null)
        OutlinedButton.icon(
          onPressed: () =>
              onChanger(filtres.copyWith(effacer: const <String>{'date'})),
          icon: const Icon(Icons.event_busy_outlined, size: 18),
          label: Text(textes.pisteSansDate),
        ),
      if (filtres.invites != null)
        OutlinedButton.icon(
          onPressed: () =>
              onChanger(filtres.copyWith(effacer: const <String>{'invites'})),
          icon: const Icon(Icons.group_off_outlined, size: 18),
          label: Text(textes.pisteSansSeuil('${filtres.invites}')),
        ),
      if (filtres.budgetMax != null)
        OutlinedButton.icon(
          onPressed: () =>
              onChanger(filtres.copyWith(effacer: const <String>{'budget'})),
          icon: const Icon(Icons.payments_outlined, size: 18),
          label: Text(textes.pisteSansBudget),
        ),
      if (filtres.wilayaCode != null)
        OutlinedButton.icon(
          onPressed: () =>
              onChanger(filtres.copyWith(effacer: const <String>{'wilaya'})),
          icon: const Icon(Icons.public, size: 18),
          label: Text(textes.pisteToutesWilayas),
        ),
      if (filtres.equipements.isNotEmpty)
        OutlinedButton.icon(
          onPressed: () =>
              onChanger(filtres.copyWith(equipements: const <String>[])),
          icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
          label: Text(textes.pisteSansEquipements),
        ),
      if (filtres.texte != null)
        OutlinedButton.icon(
          onPressed: () =>
              onChanger(filtres.copyWith(effacer: const <String>{'texte'})),
          icon: const Icon(Icons.search_off, size: 18),
          label: Text(textes.pisteSansTexte),
        ),
    ];

    return EtatVide(
      titre: textes.resultatsVideTitre,
      explication: _explication(textes, formats),
      pistes: pistes.isEmpty
          ? <Widget>[
              OutlinedButton.icon(
                onPressed: () => onChanger(const SearchFilters()),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(textes.pisteRepartirDeZero),
              ),
            ]
          : pistes,
    );
  }

  String _explication(AppLocalizations textes, FormatsFerha formats) {
    // On nomme le critère le plus souvent responsable, du plus restrictif au
    // moins : une date prise élimine tout, un budget bas presque tout.
    if (filtres.date != null) {
      return textes.resultatsVideDate(
        formats.date(filtres.date!),
        filtres.creneau.auMilieuDUnePhrase(textes),
      );
    }
    if (filtres.budgetMax != null) return textes.resultatsVideBudget;
    if (filtres.invites != null) {
      return textes.resultatsVideInvites('${filtres.invites}');
    }
    if (nomWilaya != null) return textes.resultatsVideWilaya(nomWilaya!);
    return textes.resultatsVideDefaut;
  }
}
