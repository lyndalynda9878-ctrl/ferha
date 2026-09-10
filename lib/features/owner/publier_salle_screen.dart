import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/ferha_colors.dart';
import '../../core/theme/ferha_radii.dart';
import '../search/search_providers.dart';
import '../search/widgets/etats.dart';
import 'nouvelle_salle.dart';
import 'owner_messages.dart';
import 'owner_providers.dart';

/// Inscrire une salle — écran 10 des maquettes (§4.3, OWN-01).
///
/// UNE ACTION PAR ÉCRAN, ET DES ÉTAPES COURTES. C'est le chapeau du flux D des
/// maquettes : « conçu pour Karim, 45 ans, peu à l'aise avec l'informatique ».
/// Quatre questions posées une par une valent mieux qu'un formulaire de trente
/// champs — celui-là, on le referme.
///
/// QUATRE ÉTAPES AUJOURD'HUI, CINQ DEMAIN. OWN-01 en annonce cinq : identité,
/// localisation, capacité, équipements, photos. Les photos (OWN-02) demandent
/// leur propre écran, leur compression et un `venue_id` pour leur chemin de
/// Storage : elles viennent à l'étape suivante et se glisseront ici sans rien
/// déplacer. On n'affiche donc PAS « étape 1 sur 5 » aujourd'hui : annoncer une
/// cinquième étape qui n'existe pas ferait chercher ce qui manque.
///
/// TOUT L'ÉTAT VIT DANS CE `State`, ET C'EST CE QUI FAIT QUE REVENIR NE PERD
/// RIEN. Les étapes ne sont pas des routes : changer d'étape ne démonte rien,
/// ni la valeur, ni les `TextEditingController`. Un formulaire découpé en
/// quatre écrans poussés l'un sur l'autre perdrait tout au premier retour —
/// et un propriétaire qui retape son nom de salle deux fois abandonne.
///
/// LA SALLE N'EXISTE QU'À LA FIN, ET EN BROUILLON. `creer_salle()` (017) est
/// appelée une seule fois, au bout de l'étape 4 ; elle écrit la salle, ses
/// équipements et ses types en une transaction. Rien n'est enregistré avant :
/// un formulaire abandonné à l'étape 2 ne laisse aucune trace.
class PublierSalleScreen extends ConsumerStatefulWidget {
  /// Crée le formulaire d'inscription.
  const PublierSalleScreen({super.key});

  @override
  ConsumerState<PublierSalleScreen> createState() => _PublierSalleScreenState();
}

class _PublierSalleScreenState extends ConsumerState<PublierSalleScreen> {
  /// Ce qui est rempli. Une seule valeur, remplacée à chaque frappe.
  NouvelleSalle _salle = const NouvelleSalle();

  EtapePublication _etape = EtapePublication.identite;

  /// Les contrôleurs vivent ici, et non dans les étapes.
  ///
  /// C'est le pendant de l'état : un contrôleur créé dans le `build` d'une
  /// étape serait recréé — donc vidé — à chaque retour. Ils sont créés une fois
  /// et rendus une fois.
  final _nom = TextEditingController();
  final _description = TextEditingController();
  final _commune = TextEditingController();
  final _capacite = TextEditingController();
  final _superficie = TextEditingController();
  final _parking = TextEditingController();

  bool _envoiEnCours = false;
  String? _erreur;

  @override
  void dispose() {
    _nom.dispose();
    _description.dispose();
    _commune.dispose();
    _capacite.dispose();
    _superficie.dispose();
    _parking.dispose();
    super.dispose();
  }

  void _modifie(NouvelleSalle salle) => setState(() {
    _salle = salle;
    // Le refus d'un envoi précédent ne survit pas à une correction : on vient
    // justement de changer ce qu'il reprochait.
    _erreur = null;
  });

  void _reculer() {
    if (_etape.index > 0) {
      setState(() => _etape = EtapePublication.values[_etape.index - 1]);
      return;
    }

    // Plus d'étape derrière : on quitte le formulaire.
    //
    // `canPop` ET NON `pop` SEUL. Cet écran est presque toujours poussé
    // par-dessus le profil ou le tableau de bord, et il y a alors quelque chose
    // à dépiler. Mais on peut aussi y arriver sans pile : un lien direct sur le
    // web, ou le retour de la connexion — `connexion_screen` fait justement un
    // `go(retour)` quand elle n'a rien à dépiler elle-même, et le formulaire se
    // retrouve seul. `pop()` lève alors « There is nothing to pop », et le
    // bouton retour casse l'écran au lieu de le fermer.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(FerhaRoutes.profil);
    }
  }

  Future<void> _continuer() async {
    if (!_salle.estComplete(_etape)) return;

    if (_etape.index < EtapePublication.values.length - 1) {
      setState(() => _etape = EtapePublication.values[_etape.index + 1]);
      return;
    }

    await _creer();
  }

  Future<void> _creer() async {
    setState(() {
      _envoiEnCours = true;
      _erreur = null;
    });

    try {
      final venueId = await ref
          .read(publicationDeSalleServiceProvider)
          .creer(_salle);
      if (!mounted) return;

      // pushReplacement : le récapitulatif prend la place du formulaire. La
      // salle existe maintenant, et le bouton retour ne doit pas ramener sur un
      // formulaire qui la recréerait en double.
      context.pushReplacement(FerhaRoutes.publierRecapitulatifDe(venueId));
    } on Object catch (erreur) {
      if (!mounted) return;
      setState(() => _erreur = messageErreurPublication(erreur));
    } finally {
      if (mounted) setState(() => _envoiEnCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final manque = _salle.ceQuiManque(_etape);
    final derniere = _etape.index == EtapePublication.values.length - 1;

    return Scaffold(
      appBar: AppBar(
        // Le retour de la barre fait la même chose que le retour d'étape : sur
        // la première, il quitte. Deux gestes qui ont l'air pareils doivent
        // faire pareil.
        leading: BackButton(onPressed: _envoiEnCours ? null : _reculer),
        title: Text(_etape.titre),
      ),
      body: Column(
        children: <Widget>[
          _Progression(etape: _etape),
          Expanded(
            child: ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 24),
              children: <Widget>[
                Text(
                  _etape.explication,
                  style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
                ),
                const SizedBox(height: 20),
                switch (_etape) {
                  EtapePublication.identite => _EtapeIdentite(
                    nom: _nom,
                    description: _description,
                    salle: _salle,
                    onChange: _modifie,
                  ),
                  EtapePublication.lieu => _EtapeLieu(
                    commune: _commune,
                    salle: _salle,
                    onChange: _modifie,
                  ),
                  EtapePublication.capacite => _EtapeCapacite(
                    capacite: _capacite,
                    superficie: _superficie,
                    parking: _parking,
                    salle: _salle,
                    onChange: _modifie,
                  ),
                  EtapePublication.equipements => _EtapeEquipements(
                    salle: _salle,
                    onChange: _modifie,
                  ),
                },
                if (_erreur != null) ...<Widget>[
                  const SizedBox(height: 20),
                  _Refus(message: _erreur!),
                ],
              ],
            ),
          ),
          _BarreContinuer(
            manque: manque,
            derniere: derniere,
            enCours: _envoiEnCours,
            onContinuer: _continuer,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// L'enveloppe : la progression, et le bouton du bas
// =============================================================================

/// « Étape 2 sur 4 », et une barre qui se remplit.
///
/// Le chiffre ET la barre, pas l'un ou l'autre : la barre dit d'un coup d'œil
/// combien il reste, le chiffre dit exactement où l'on est. C'est ce que fait
/// l'écran 10, qui écrit « Étape 4 sur 5 » en toutes lettres.
class _Progression extends StatelessWidget {
  const _Progression({required this.etape});

  final EtapePublication etape;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Étape ${etape.rang} sur ${EtapePublication.total}',
            style: text.labelSmall?.copyWith(
              color: colors.inkTertiary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: FerhaRadii.chipBorder,
            child: LinearProgressIndicator(
              value: etape.rang / EtapePublication.total,
              minHeight: 6,
              backgroundColor: colors.surfaceSecondary,
              color: colors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Le bouton du bas, et ce qui l'empêche de s'allumer.
///
/// « CONTINUER » RESTE ÉTEINT TANT QU'UN CHAMP OBLIGATOIRE MANQUE, ET DIT
/// LEQUEL. Un bouton gris sans explication fait relire trois champs pour
/// trouver le vide ; la phrase le désigne. Elle est posée au-dessus du bouton,
/// là où le doigt allait — pas en haut de l'écran, qu'on ne regarde plus.
///
/// Le bouton éteint ne se peint pas en ambre : c'est le thème qui s'en charge
/// (`boutons_test.dart` le vérifie), et il n'y a rien à écrire ici pour cela.
class _BarreContinuer extends StatelessWidget {
  const _BarreContinuer({
    required this.manque,
    required this.derniere,
    required this.enCours,
    required this.onContinuer,
  });

  /// Ce qui manque, ou `null` si l'étape est complète.
  final String? manque;

  /// Vrai sur la dernière étape : le bouton ne dit plus « Continuer ».
  final bool derniere;

  final bool enCours;
  final VoidCallback onContinuer;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.rule)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (manque != null) ...<Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: colors.inkSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      manque!,
                      style: text.bodySmall?.copyWith(
                        color: colors.inkSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (manque != null || enCours) ? null : onContinuer,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsetsDirectional.symmetric(vertical: 16),
                ),
                child: enCours
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(derniere ? 'Inscrire ma salle' : 'Continuer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Étape 1 — l'identité
// =============================================================================

class _EtapeIdentite extends StatelessWidget {
  const _EtapeIdentite({
    required this.nom,
    required this.description,
    required this.salle,
    required this.onChange,
  });

  final TextEditingController nom;
  final TextEditingController description;
  final NouvelleSalle salle;
  final ValueChanged<NouvelleSalle> onChange;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _Intitule('Nom de la salle'),
        const SizedBox(height: 8),
        TextField(
          controller: nom,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 120,
          decoration: const InputDecoration(hintText: 'Salle El Bahia'),
          onChanged: (v) => onChange(salle.copyWith(nom: v)),
        ),
        const SizedBox(height: 12),
        const _Intitule('Description'),
        const SizedBox(height: 8),
        TextField(
          controller: description,
          maxLines: 4,
          maxLength: 600,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText:
                'Ce qui la distingue : la vue, le jardin, la salle des femmes…',
          ),
          onChanged: (v) => onChange(salle.copyWith(description: v)),
        ),
        const _Facultatif(),
      ],
    );
  }
}

// =============================================================================
// Étape 2 — le lieu
// =============================================================================

class _EtapeLieu extends ConsumerWidget {
  const _EtapeLieu({
    required this.commune,
    required this.salle,
    required this.onChange,
  });

  final TextEditingController commune;
  final NouvelleSalle salle;
  final ValueChanged<NouvelleSalle> onChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // LES 58 WILAYAS, ET NON CELLES QUI ONT DÉJÀ DES SALLES. La recherche
    // n'affiche que les secondes, pour ne pas proposer une puce qui ne mène
    // nulle part ; ici c'est l'inverse — c'est la première salle d'une wilaya
    // qui l'ouvre au catalogue.
    final wilayas = ref.watch(toutesLesWilayasProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _Intitule('Wilaya'),
        const SizedBox(height: 8),
        switch (wilayas) {
          AsyncError(:final error) => EtatErreur(
            titre: 'La liste des wilayas n’a pas pu être chargée',
            erreur: error,
            onReessayer: () => ref.invalidate(toutesLesWilayasProvider),
          ),
          AsyncData(:final value) => DropdownButtonFormField<String>(
            initialValue: salle.wilayaCode,
            isExpanded: true,
            decoration: const InputDecoration(
              hintText: 'Choisissez une wilaya',
            ),
            items: <DropdownMenuItem<String>>[
              for (final w in value)
                DropdownMenuItem<String>(
                  value: w.code,
                  // Le code ET le nom : c'est ainsi qu'une wilaya s'écrit
                  // partout en Algérie, et « 31 » se cherche plus vite qu'on ne
                  // fait défiler jusqu'à « Oran ».
                  child: Text('${w.code} · ${w.nom}'),
                ),
            ],
            onChanged: (v) => onChange(salle.copyWith(wilayaCode: v)),
          ),
          _ => const Padding(
            padding: EdgeInsetsDirectional.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
        },
        const SizedBox(height: 20),
        const _Intitule('Commune'),
        const SizedBox(height: 8),
        TextField(
          controller: commune,
          textCapitalization: TextCapitalization.words,
          maxLength: 80,
          decoration: const InputDecoration(hintText: 'Bir El Djir'),
          onChanged: (v) => onChange(salle.copyWith(commune: v)),
        ),
      ],
    );
  }
}

// =============================================================================
// Étape 3 — la capacité
// =============================================================================

class _EtapeCapacite extends StatelessWidget {
  const _EtapeCapacite({
    required this.capacite,
    required this.superficie,
    required this.parking,
    required this.salle,
    required this.onChange,
  });

  final TextEditingController capacite;
  final TextEditingController superficie;
  final TextEditingController parking;
  final NouvelleSalle salle;
  final ValueChanged<NouvelleSalle> onChange;

  /// Un champ vide vaut « non renseigné », et non zéro.
  ///
  /// C'est la distinction du §6 sur le parking : `NULL` veut dire « je ne sais
  /// pas », `0` veut dire « il n'y en a pas ». Effacer le champ doit donc
  /// revenir à « non renseigné », et non poser un zéro qui affirmerait quelque
  /// chose que le propriétaire n'a pas dit.
  static int? _nombre(String texte) {
    final propre = texte.trim();
    if (propre.isEmpty) return null;
    return int.tryParse(propre);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _Intitule('Capacité assise'),
        const SizedBox(height: 8),
        TextField(
          controller: capacite,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: const InputDecoration(
            hintText: '300',
            suffixText: 'couverts',
          ),
          onChanged: (v) {
            final n = _nombre(v);
            // Un zéro n'est pas une capacité : `venues` exige > 0, et laisser
            // « Continuer » s'allumer dessus mènerait à un refus FE031.
            onChange(salle.copyWith(capacite: (n ?? 0) > 0 ? n : null));
          },
        ),
        const SizedBox(height: 12),
        const _Intitule('Superficie'),
        const SizedBox(height: 8),
        TextField(
          controller: superficie,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: const InputDecoration(hintText: '600', suffixText: 'm²'),
          onChanged: (v) {
            final n = _nombre(v);
            onChange(salle.copyWith(superficie: (n ?? 0) > 0 ? n : null));
          },
        ),
        const SizedBox(height: 12),
        const _Intitule('Places de parking'),
        const SizedBox(height: 8),
        TextField(
          controller: parking,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: const InputDecoration(
            hintText: '60',
            suffixText: 'places',
          ),
          // Zéro est une VRAIE réponse ici, contrairement aux deux champs du
          // dessus : « pas de parking » se dit, et se distingue de « je ne sais
          // pas ». On n'écarte donc pas le zéro.
          onChanged: (v) => onChange(salle.copyWith(parking: _nombre(v))),
        ),
        const _Facultatif(
          texte:
              'Superficie et parking sont facultatifs — mais le parking est '
              'la deuxième chose que les familles regardent.',
        ),
      ],
    );
  }
}

// =============================================================================
// Étape 4 — les équipements et les événements
// =============================================================================

class _EtapeEquipements extends ConsumerWidget {
  const _EtapeEquipements({required this.salle, required this.onChange});

  final NouvelleSalle salle;
  final ValueChanged<NouvelleSalle> onChange;

  void _bascule(
    Set<String> ensemble,
    String code,
    void Function(Set<String>) f,
  ) {
    final copie = Set<String>.of(ensemble);
    if (!copie.remove(code)) copie.add(code);
    f(copie);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equipements = ref.watch(equipementsParCategorieProvider);
    final types = ref.watch(typesEvenementProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        switch (equipements) {
          AsyncError(:final error) => EtatErreur(
            titre: 'La liste des équipements n’a pas pu être chargée',
            erreur: error,
            onReessayer: () => ref.invalidate(equipementsParCategorieProvider),
          ),
          AsyncData(:final value) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final categorie in value.entries) ...<Widget>[
                _Intitule(libelleCategorieEquipement(categorie.key)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final e in categorie.value)
                      FilterChip(
                        label: Text(e.libelle),
                        selected: salle.equipements.contains(e.code),
                        onSelected: (_) => _bascule(
                          salle.equipements,
                          e.code,
                          (s) => onChange(salle.copyWith(equipements: s)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ],
          ),
          _ => const Padding(
            padding: EdgeInsetsDirectional.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
        },

        const _Intitule('Événements accueillis'),
        const SizedBox(height: 6),
        Text(
          // La règle de `venue_event_types` (010), dite à celui qui en dépend :
          // « aucune ligne = la salle accepte tout ». Sans cette phrase, un
          // propriétaire pressé n'en coche aucun en croyant se fermer des
          // portes, alors qu'il se les ouvre toutes.
          'Si vous n’en cochez aucun, votre salle apparaîtra pour tous les '
          'types d’événement.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.ferhaColors.inkTertiary,
          ),
        ),
        const SizedBox(height: 10),
        switch (types) {
          AsyncData(:final value) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final t in value)
                FilterChip(
                  label: Text(t.libelle),
                  selected: salle.typesEvenement.contains(t.code),
                  onSelected: (_) => _bascule(
                    salle.typesEvenement,
                    t.code,
                    (s) => onChange(salle.copyWith(typesEvenement: s)),
                  ),
                ),
            ],
          ),
          // Un référentiel de puces facultatives ne mérite pas un état d'erreur
          // qui bloquerait l'étape : sans lui, la salle accepte tout, ce qui
          // est le comportement par défaut de toute façon.
          _ => const SizedBox.shrink(),
        },
      ],
    );
  }
}

// =============================================================================
// Pièces communes
// =============================================================================

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

/// Dit qu'on peut passer sans remplir.
///
/// Écrit plutôt que sous-entendu : un champ vide au-dessus d'un bouton allumé
/// laisse croire qu'on a oublié quelque chose, et on cherche quoi.
class _Facultatif extends StatelessWidget {
  const _Facultatif({
    this.texte = 'Facultatif — vous pourrez l’ajouter plus tard.',
  });

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Text(
      texte,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: context.ferhaColors.inkTertiary),
    );
  }
}

/// Le refus de la base, à côté du bouton qui l'a produit.
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
