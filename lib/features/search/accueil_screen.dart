import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/ferha_colors.dart';
import '../../core/theme/ferha_radii.dart';
import 'search_filters.dart';
import 'search_providers.dart';
import 'widgets/etats.dart';
import 'widgets/venue_card.dart';

/// Écran 1 des maquettes — l'accueil EST la recherche.
///
/// « Trois critères suffisent à lancer une requête : où, quand, combien. »
/// Tout est donc au-dessus de la ligne de flottaison, et le bouton Rechercher
/// n'attend jamais qu'on ait tout rempli : chercher sans aucun critère est
/// légitime, cela montre le catalogue.
///
/// AUCUNE CONNEXION N'EST DEMANDÉE ICI. Chercher et consulter se font sans
/// compte (§3) : c'est au moment d'agir que la question se pose.
class AccueilScreen extends ConsumerStatefulWidget {
  /// Crée l'écran d'accueil.
  const AccueilScreen({super.key});

  @override
  ConsumerState<AccueilScreen> createState() => _AccueilScreenState();
}

class _AccueilScreenState extends ConsumerState<AccueilScreen> {
  final _texte = TextEditingController();
  SearchFilters _filtres = const SearchFilters();

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  void _rechercher() {
    final filtres = _filtres.copyWith(
      texte: _texte.text.trim().isEmpty ? null : _texte.text.trim(),
    );
    context.push(
      Uri(
        path: FerhaRoutes.resultats,
        queryParameters: filtres.versParametres(),
      ).toString(),
    );
  }

  Future<void> _choisirDate() async {
    final maintenant = DateTime.now();
    final choix = await showDatePicker(
      context: context,
      initialDate: _filtres.date ?? maintenant.add(const Duration(days: 30)),
      firstDate: maintenant,
      // Le calendrier de disponibilité couvre 18 mois (§4.2, CLI-04) : on ne
      // laisse pas chercher au-delà de ce qu'on sait dire.
      lastDate: DateTime(
        maintenant.year,
        maintenant.month + 18,
        maintenant.day,
      ),
      helpText: 'Date de l’événement',
      cancelText: 'Annuler',
      confirmText: 'Choisir',
    );
    if (choix != null) {
      setState(() => _filtres = _filtres.copyWith(date: choix));
    }
  }

  Future<void> _choisirInvites() async {
    final controleur = TextEditingController(
      text: _filtres.invites?.toString() ?? '',
    );
    final valeur = await showDialog<int?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nombre d’invités'),
        content: TextField(
          controller: controleur,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Couverts',
            helperText: 'Sert aussi au calcul du prix.',
          ),
          onSubmitted: (v) => Navigator.of(context).pop(int.tryParse(v.trim())),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(-1),
            child: const Text('Effacer'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(int.tryParse(controleur.text.trim())),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    controleur.dispose();

    if (!mounted || valeur == null) return;
    setState(() {
      _filtres = valeur < 0
          ? _filtres.copyWith(effacer: const <String>{'invites'})
          : _filtres.copyWith(invites: valeur);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final wilayas = ref.watch(wilayasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trouvez votre salle'),
        titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: colors.ink,
        ),
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 32),
        children: <Widget>[
          // Champ libre : wilaya, commune ou nom de salle.
          TextField(
            controller: _texte,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _rechercher(),
            decoration: const InputDecoration(
              hintText: 'Wilaya, commune ou nom de salle',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 16),

          // Puces de wilaya — seulement celles qui ont des salles.
          wilayas.when(
            loading: () => const _PucesEnAttente(),
            error: (_, _) => const SizedBox.shrink(),
            data: (liste) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: liste
                  .map(
                    (w) => ChoiceChip(
                      label: Text(w.nom),
                      selected: _filtres.wilayaCode == w.code,
                      onSelected: (choisie) => setState(() {
                        _filtres = choisie
                            ? _filtres.copyWith(wilayaCode: w.code)
                            : _filtres.copyWith(
                                effacer: const <String>{'wilaya'},
                              );
                      }),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: 16),

          // Quand, et combien.
          Row(
            children: <Widget>[
              Expanded(
                child: _Critere(
                  icone: Icons.calendar_today_outlined,
                  valeur: _filtres.date == null
                      ? 'Date'
                      : dateEnFrancais(_filtres.date!),
                  rempli: _filtres.date != null,
                  onTap: _choisirDate,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Critere(
                  icone: Icons.group_outlined,
                  valeur: _filtres.invites == null
                      ? 'Invités'
                      : '${_filtres.invites} invités',
                  rempli: _filtres.invites != null,
                  onTap: _choisirInvites,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Le créneau : « journee » occupe midi ET soir (§5.1).
          SegmentedButton<Creneau>(
            segments: Creneau.values
                .map(
                  (c) =>
                      ButtonSegment<Creneau>(value: c, label: Text(c.libelle)),
                )
                .toList(growable: false),
            selected: <Creneau>{_filtres.creneau},
            onSelectionChanged: (choix) => setState(
              () => _filtres = _filtres.copyWith(creneau: choix.first),
            ),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 20),

          const _Intitule('Type d’événement'),
          const SizedBox(height: 8),
          // Les puces viennent du référentiel event_types : le filtre envoie
          // le code, l'écran affiche le libellé. Depuis 010, il filtre pour de
          // bon — cocher « Mariage » retire vraiment des salles.
          ref
              .watch(typesEvenementProvider)
              .when(
                loading: () => const _PucesEnAttente(),
                error: (_, _) => const SizedBox.shrink(),
                data: (types) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: types
                      .map(
                        (type) => ChoiceChip(
                          label: Text(type.libelle),
                          selected: _filtres.typeEvenement == type.code,
                          onSelected: (choisi) => setState(() {
                            _filtres = choisi
                                ? _filtres.copyWith(typeEvenement: type.code)
                                : _filtres.copyWith(
                                    effacer: const <String>{'type'},
                                  );
                          }),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
          const SizedBox(height: 24),

          FilledButton(
            onPressed: _rechercher,
            style: FilledButton.styleFrom(
              padding: const EdgeInsetsDirectional.symmetric(vertical: 16),
            ),
            child: const Text('Rechercher'),
          ),
          const SizedBox(height: 32),

          _MieuxNotees(filtres: _filtres),
        ],
      ),
    );
  }
}

/// « Les mieux notées », en bas de l'accueil.
///
/// Le titre s'adapte : tant qu'aucune salle n'a d'avis, parler des « mieux
/// notées » serait faux — c'est simplement une sélection.
class _MieuxNotees extends ConsumerWidget {
  const _MieuxNotees({required this.filtres});

  final SearchFilters filtres;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Seule la wilaya est reprise : cette liste est une vitrine, pas le
    // résultat de la recherche en cours.
    final vitrine = SearchFilters(
      wilayaCode: filtres.wilayaCode,
      creneau: filtres.creneau,
    );
    final resultat = ref.watch(mieuxNoteesProvider(vitrine));
    final wilayas = ref.watch(wilayasProvider).value;
    final nomWilaya = filtres.wilayaCode == null
        ? null
        : wilayas
              ?.where((w) => w.code == filtres.wilayaCode)
              .map((w) => w.nom)
              .firstOrNull;

    return resultat.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _Intitule('Sélection'),
          const SizedBox(height: 12),
          const CarteSquelette(),
        ],
      ),
      error: (erreur, _) => _Encart(
        child: EtatErreur(
          erreur: erreur,
          onReessayer: () => ref.invalidate(mieuxNoteesProvider(vitrine)),
        ),
      ),
      data: (donnees) {
        if (donnees.salles.isEmpty) {
          return _Encart(
            child: EtatVide(
              titre: 'Aucune salle publiée ici',
              explication: nomWilaya == null
                  ? 'Le catalogue est encore vide. Lancez les données de '
                        'démonstration, ou publiez une première salle.'
                  : 'Aucune salle n’est publiée à $nomWilaya pour l’instant. '
                        'Essayez une autre wilaya.',
            ),
          );
        }

        // Une salle notée dans le lot suffit à justifier le titre.
        final ilYADesNotes = donnees.salles.any((s) => s.estNotee);
        final titre = ilYADesNotes ? 'Les mieux notées' : 'Salles à découvrir';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Intitule(nomWilaya == null ? titre : '$titre à $nomWilaya'),
            const SizedBox(height: 12),
            for (final salle in donnees.salles.take(3)) ...<Widget>[
              VenueCard(
                salle: salle,
                dense: true,
                onTap: () => context.push(
                  Uri(
                    path: FerhaRoutes.salleDe(salle.id),
                    queryParameters: vitrine.versParametres(),
                  ).toString(),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

/// Intitulé de section — capitales espacées des maquettes.
class _Intitule extends StatelessWidget {
  const _Intitule(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    return Text(
      texte.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: colors.inkTertiary,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Un critère cliquable : date, invités.
class _Critere extends StatelessWidget {
  const _Critere({
    required this.icone,
    required this.valeur,
    required this.rempli,
    required this.onTap,
  });

  final IconData icone;
  final String valeur;
  final bool rempli;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Material(
      color: colors.surfaceSecondary,
      borderRadius: FerhaRadii.cardBorder,
      child: InkWell(
        onTap: onTap,
        borderRadius: FerhaRadii.cardBorder,
        child: Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            borderRadius: FerhaRadii.cardBorder,
            border: Border.all(color: rempli ? colors.primary : colors.rule),
          ),
          child: Row(
            children: <Widget>[
              Icon(icone, size: 18, color: colors.inkTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  valeur,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(
                    color: rempli ? colors.ink : colors.inkTertiary,
                    fontWeight: rempli ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PucesEnAttente extends StatelessWidget {
  const _PucesEnAttente();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    return Wrap(
      spacing: 8,
      children: List<Widget>.generate(
        4,
        (i) => Container(
          width: 74,
          height: 32,
          decoration: BoxDecoration(
            color: colors.surfaceSecondary,
            borderRadius: FerhaRadii.chipBorder,
          ),
        ),
      ),
    );
  }
}

/// Borne la hauteur d'un état plein écran quand il vit dans une liste.
class _Encart extends StatelessWidget {
  const _Encart({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(height: 280, child: child);
}
