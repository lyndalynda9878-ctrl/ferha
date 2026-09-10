import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/router/routes.dart';
import '../../core/theme/ferha_colors.dart';
import '../../core/theme/ferha_radii.dart';
import '../../core/widgets/photo_salle.dart';
import '../search/widgets/etats.dart';
import 'compression_photo.dart';
import 'nouvelle_salle.dart';
import 'owner_messages.dart';
import 'owner_providers.dart';
import 'owner_repository.dart';
import 'photo_de_salle.dart';
import 'widgets/progression_publication.dart';

/// Le nombre de photos sans lequel on ne peut pas continuer (§4.3, OWN-02).
///
/// SECOND EXEMPLAIRE ASSUMÉ DE `photos_min()`. Le premier est en SQL (021), et
/// c'est lui qui compte : `envoyer_salle_en_validation()` refuse en FE041, quel
/// que soit le client. Celui-ci ne protège rien — il éteint « Continuer » avant
/// qu'on appuie, plutôt que de laisser aller jusqu'au récapitulatif pour y
/// essuyer un refus. Demander le nombre à la base à l'ouverture de l'écran
/// coûterait un aller-retour pour une valeur qui ne change jamais.
///
/// Deux exemplaires, pas trois — c'est la même règle que pour le téléphone
/// (`telephone.dart` et `telephone_valide()`), et chacun est épinglé par son
/// test.
const int photosMinimum = 5;

/// Le nombre de photos au-delà duquel la base refuse — `photos_max()` (021).
const int photosMaximum = 20;

/// Où en est une photo qu'on vient de choisir.
enum EtapeEnvoi {
  /// Choisie, pas encore traitée. Les photos attendent leur tour de
  /// compression.
  attente,

  /// En cours de réduction et de réencodage sur l'appareil.
  compression,

  /// En cours d'envoi vers le bucket.
  envoi,

  /// L'une des deux a échoué. Renvoyable seule.
  echec,
}

/// Une photo choisie, en route vers la galerie.
///
/// Elle vit dans l'écran et nulle part ailleurs : dès qu'elle arrive en base,
/// elle devient une [PhotoDeSalle] et disparaît d'ici.
@immutable
class EnvoiDePhoto {
  /// Crée un envoi.
  const EnvoiDePhoto({
    required this.cle,
    required this.source,
    this.etape = EtapeEnvoi.attente,
    this.apercu,
    this.message,
  });

  /// Un identifiant local, le temps de l'envoi. Il sert de `Key` à la vignette
  /// et à retrouver l'envoi dans la liste.
  final String cle;

  /// Le fichier choisi, tel que l'a rendu le sélecteur.
  final XFile source;

  /// Où en est cet envoi.
  final EtapeEnvoi etape;

  /// Les octets COMPRESSÉS, dès qu'ils existent.
  ///
  /// C'est eux qu'on affiche, et jamais l'original : décoder six photos de
  /// quatre mégaoctets pour en faire des vignettes de soixante-douze pixels
  /// remplirait la mémoire sans que rien ne s'affiche plus vite.
  final Uint8List? apercu;

  /// Ce qui a échoué, en français.
  final String? message;

  /// Rend une copie modifiée.
  EnvoiDePhoto copyWith({
    EtapeEnvoi? etape,
    Uint8List? apercu,
    String? message,
  }) => EnvoiDePhoto(
    cle: cle,
    source: source,
    etape: etape ?? this.etape,
    apercu: apercu ?? this.apercu,
    message: message,
  );
}

/// L'étape des photos (§4.3, OWN-02 ; §7.3 ; écran 10 des maquettes).
///
/// LA CINQUIÈME ÉTAPE, ET LA PREMIÈRE QUI PARLE D'UNE SALLE QUI EXISTE. Les
/// quatre précédentes remplissent un formulaire ; celle-ci écrit dans une salle
/// déjà créée en brouillon, parce qu'une photo a besoin d'un `venue_id` pour son
/// chemin `{venue_id}/{uuid}.webp`. C'est aussi ce qui la rend REPRENABLE : un
/// brouillon abandonné ici se rouvre ici, depuis le tableau de bord.
///
/// LE TRAVAIL EST EN PIPELINE, ET C'EST CE QUI FAIT TENIR SIX PHOTOS EN MOINS DE
/// VINGT SECONDES. Une photo à la fois est compressée — l'encodeur du navigateur
/// travaille sur le fil principal, en lancer six ensemble figerait l'écran —,
/// mais dès qu'une est prête, son envoi part SANS qu'on l'attende : le réseau de
/// la première recouvre la compression de la deuxième. Tout compresser puis tout
/// envoyer prendrait la somme des deux ; ici on paie le maximum, pas la somme.
///
/// UNE PHOTO QUI ÉCHOUE ÉCHOUE SEULE. Chaque envoi porte son état et son refus ;
/// « Renvoyer » la remet dans la file, et les cinq autres ne sont pas refaites.
/// C'est la différence entre une 4G qui coupe une fois et un propriétaire qui
/// recommence tout.
///
/// CE QUE CET ÉCRAN N'AFFICHE PAS, ET C'EST DÉLIBÉRÉ. La maquette porte deux
/// choses qu'on ne reprend pas : « les salles qui ont plus de 10 photos
/// reçoivent trois fois plus de demandes » — un chiffre qu'aucune donnée du
/// projet ne soutient —, et un conseil automatique « il manque une photo du
/// parking », qui supposerait d'analyser les images. À leur place, une phrase
/// fixe qui dit la même chose sans rien inventer.
class PhotosSalleScreen extends ConsumerStatefulWidget {
  /// Crée l'écran des photos.
  const PhotosSalleScreen({required this.venueId, super.key});

  /// La salle, en brouillon, à qui ces photos appartiennent.
  final String venueId;

  @override
  ConsumerState<PhotosSalleScreen> createState() => _PhotosSalleScreenState();
}

class _PhotosSalleScreenState extends ConsumerState<PhotosSalleScreen> {
  /// Les photos déjà en base, dans l'ordre d'affichage.
  List<PhotoDeSalle> _enregistrees = const <PhotoDeSalle>[];

  /// Celles qui sont en route.
  final List<EnvoiDePhoto> _envois = <EnvoiDePhoto>[];

  bool _chargement = true;
  Object? _echecDeLecture;

  /// Un refus qui ne concerne aucune vignette en particulier — le
  /// réordonnancement, une suppression.
  String? _erreur;

  /// Vrai pendant qu'une suppression ou un réordonnancement est en cours.
  bool _ecritureEnCours = false;

  /// Vrai tant que la pompe tourne. Voir [_travailler].
  bool _pompeEnMarche = false;

  int _compteur = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_lire());
  }

  // ---------------------------------------------------------------------------
  // Lire
  // ---------------------------------------------------------------------------

  Future<void> _lire() async {
    setState(() {
      _chargement = true;
      _echecDeLecture = null;
    });

    try {
      final photos = await ref
          .read(ownerRepositoryProvider)
          .photos(widget.venueId);
      if (!mounted) return;
      setState(() {
        _enregistrees = photos;
        _chargement = false;
      });
    } on Object catch (erreur) {
      if (!mounted) return;
      setState(() {
        _echecDeLecture = erreur;
        _chargement = false;
      });
    }
  }

  /// Le geste de « tirer vers le bas », auquel renvoient FE039 et FE040.
  ///
  /// Il ne repasse PAS par le squelette : la liste est déjà à l'écran, et la
  /// faire disparaître une demi-seconde pour la remettre serait un clignotement
  /// pour rien.
  Future<void> _rafraichir() async {
    try {
      final photos = await ref
          .read(ownerRepositoryProvider)
          .photos(widget.venueId);
      if (!mounted) return;
      setState(() {
        _enregistrees = photos;
        _erreur = null;
      });
    } on Object catch (erreur) {
      if (!mounted) return;
      setState(() => _erreur = messageErreurPhotos(erreur));
    }
  }

  // ---------------------------------------------------------------------------
  // Choisir
  // ---------------------------------------------------------------------------

  /// Ce qu'on peut encore ajouter avant d'atteindre [photosMaximum].
  int get _placesRestantes =>
      photosMaximum - _enregistrees.length - _envois.length;

  Future<void> _depuisAppareilPhoto() async {
    if (_placesRestantes <= 0) return;
    try {
      final prise = await ref.read(selecteurDePhotosProvider).appareilPhoto();
      if (prise != null) _enfiler(<XFile>[prise]);
    } on Object catch (erreur) {
      if (!mounted) return;
      setState(() => _erreur = messageErreurPhotos(erreur));
    }
  }

  Future<void> _depuisGalerie() async {
    final places = _placesRestantes;
    if (places <= 0) return;

    try {
      // ON DEMANDE AU SÉLECTEUR DE BORNER, plutôt que de couper après coup :
      // choisir dix photos pour s'en voir refuser quatre est désagréable, et le
      // sélecteur d'Android sait dire « vous pouvez en choisir 6 ».
      final choisies = await ref
          .read(selecteurDePhotosProvider)
          .galerie(maximum: places);
      if (choisies.isNotEmpty) {
        // La borne du sélecteur n'est pas garantie — `limit` « may be ignored
        // by platforms that cannot support it », et un `<input multiple>` de
        // navigateur l'ignore. On la repose donc ici, sans quoi la base
        // refuserait les photos de trop une par une (FE038).
        _enfiler(choisies.take(places).toList(growable: false));
      }
    } on Object catch (erreur) {
      if (!mounted) return;
      setState(() => _erreur = messageErreurPhotos(erreur));
    }
  }

  void _enfiler(List<XFile> fichiers) {
    setState(() {
      _erreur = null;
      for (final fichier in fichiers) {
        _envois.add(EnvoiDePhoto(cle: 'envoi-${_compteur++}', source: fichier));
      }
    });
    unawaited(_travailler());
  }

  // ---------------------------------------------------------------------------
  // La pompe : compresser une par une, envoyer en parallèle
  // ---------------------------------------------------------------------------

  /// Traite la file jusqu'à ce qu'il n'y ait plus rien en attente.
  ///
  /// UNE SEULE POMPE À LA FOIS, et c'est tout le rôle de [_pompeEnMarche].
  /// Ajouter des photos pendant qu'un lot est en cours ne doit pas lancer une
  /// seconde boucle qui compresserait en même temps que la première — les deux
  /// se disputeraient le fil principal, et l'écran figerait précisément
  /// pendant qu'on lui en demande le plus.
  Future<void> _travailler() async {
    if (_pompeEnMarche) return;
    _pompeEnMarche = true;

    try {
      while (mounted) {
        final suivant = _envois
            .where((e) => e.etape == EtapeEnvoi.attente)
            .firstOrNull;
        if (suivant == null) break;
        await _compresserPuisEnvoyer(suivant.cle);
      }
    } finally {
      _pompeEnMarche = false;
    }
  }

  /// Compresse, puis LANCE l'envoi sans l'attendre.
  ///
  /// C'est la ligne qui fait le pipeline : le `unawaited` rend la main à
  /// [_travailler], qui attaque aussitôt la compression de la suivante pendant
  /// que celle-ci traverse le réseau.
  Future<void> _compresserPuisEnvoyer(String cle) async {
    _majEnvoi(cle, (e) => e.copyWith(etape: EtapeEnvoi.compression));

    final PhotoCompressee compressee;
    try {
      final envoi = _envois.where((e) => e.cle == cle).firstOrNull;
      if (envoi == null) return;

      final origine = await envoi.source.readAsBytes();
      compressee = await ref
          .read(compresseurDePhotoProvider)
          .compresser(origine);
    } on Object catch (erreur) {
      _majEnvoi(
        cle,
        (e) => e.copyWith(
          etape: EtapeEnvoi.echec,
          message: messageErreurPhotos(erreur),
        ),
      );
      return;
    }

    if (!mounted) return;

    _majEnvoi(
      cle,
      (e) => e.copyWith(etape: EtapeEnvoi.envoi, apercu: compressee.octets),
    );

    unawaited(_envoyer(cle, compressee));
  }

  Future<void> _envoyer(String cle, PhotoCompressee compressee) async {
    try {
      final photo = await ref
          .read(ownerRepositoryProvider)
          .ajouterPhoto(widget.venueId, compressee);
      if (!mounted) return;

      setState(() {
        _envois.removeWhere((e) => e.cle == cle);
        _enregistrees = <PhotoDeSalle>[..._enregistrees, photo];
      });
    } on Object catch (erreur) {
      if (!mounted) return;
      _majEnvoi(
        cle,
        (e) => e.copyWith(
          etape: EtapeEnvoi.echec,
          message: messageErreurPhotos(erreur),
        ),
      );
    }
  }

  /// Remet une photo échouée dans la file. Elle seule.
  void _renvoyer(String cle) {
    _majEnvoi(cle, (e) => e.copyWith(etape: EtapeEnvoi.attente));
    unawaited(_travailler());
  }

  void _abandonner(String cle) {
    setState(() => _envois.removeWhere((e) => e.cle == cle));
  }

  void _majEnvoi(String cle, EnvoiDePhoto Function(EnvoiDePhoto) f) {
    if (!mounted) return;
    final index = _envois.indexWhere((e) => e.cle == cle);
    if (index < 0) return;
    setState(() => _envois[index] = f(_envois[index]));
  }

  // ---------------------------------------------------------------------------
  // Réordonner, supprimer
  // ---------------------------------------------------------------------------

  /// LA LISTE BOUGE AVANT LA BASE, ET REVIENT EN ARRIÈRE SI LA BASE REFUSE.
  ///
  /// Un glisser-déposer qui attendrait un aller-retour réseau avant de bouger
  /// n'aurait pas l'air d'un glisser-déposer. On déplace donc tout de suite,
  /// on écrit derrière, et on remet l'ordre précédent en cas de refus — avec la
  /// phrase qui dit pourquoi, sans quoi la photo « reviendrait toute seule » à
  /// sa place sans explication.
  Future<void> _reordonner(int depuis, int vers) async {
    final avant = _enregistrees;

    final apres = <PhotoDeSalle>[...avant];
    // `ReorderableListView` donne l'index d'arrivée AVANT le retrait de
    // l'élément déplacé : il faut donc le décaler quand on descend.
    final destination = vers > depuis ? vers - 1 : vers;
    apres.insert(destination, apres.removeAt(depuis));

    setState(() {
      _enregistrees = apres;
      _erreur = null;
      _ecritureEnCours = true;
    });

    try {
      final rangees = await ref
          .read(ownerRepositoryProvider)
          .reordonnerPhotos(
            widget.venueId,
            apres.map((p) => p.id).toList(growable: false),
          );
      if (!mounted) return;
      // On reprend ce que la BASE rend, et non ce qu'on avait deviné : c'est
      // elle qui pose `position` et `is_cover`, et la pastille « Couverture »
      // doit dire ce qu'elle a écrit.
      setState(() => _enregistrees = rangees);
    } on Object catch (erreur) {
      if (!mounted) return;
      setState(() {
        _enregistrees = avant;
        _erreur = messageErreurPhotos(erreur);
      });
    } finally {
      if (mounted) setState(() => _ecritureEnCours = false);
    }
  }

  Future<void> _supprimer(PhotoDeSalle photo) async {
    setState(() {
      _erreur = null;
      _ecritureEnCours = true;
    });

    try {
      await ref.read(ownerRepositoryProvider).supprimerPhoto(photo.id);
      if (!mounted) return;
      // On relit plutôt que de retirer la ligne sur place : `supprimer_photo()`
      // referme les rangs derrière elle et redonne la couverture à celle qui
      // devient première. Deviner ce nouvel ordre ici serait une seconde
      // renumérotation, qui dirait un jour autre chose que la première.
      await _rafraichir();
    } on Object catch (erreur) {
      if (!mounted) return;
      setState(() => _erreur = messageErreurPhotos(erreur));
    } finally {
      if (mounted) setState(() => _ecritureEnCours = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Continuer
  // ---------------------------------------------------------------------------

  /// Ce qui empêche de continuer, ou `null`.
  String? get _ceQuiManque {
    if (_envois.any((e) => e.etape != EtapeEnvoi.echec)) {
      return 'Attendez la fin des envois en cours.';
    }
    final manquantes = photosMinimum - _enregistrees.length;
    if (manquantes > 0) {
      return manquantes == 1
          ? 'Encore une photo avant de continuer.'
          : 'Encore $manquantes photos avant de continuer.';
    }
    return null;
  }

  /// `push` ET NON `pushReplacement` : le récapitulatif s'ouvre PAR-DESSUS les
  /// photos, et son bouton retour ramène ici. C'est le contraire du formulaire,
  /// qu'on remplace en arrivant sur cet écran — y revenir créerait une seconde
  /// salle. Ici, revenir sur ses photos pour en ajouter une est légitime.
  ///
  /// L'ESPACE PROPRIÉTAIRE EST RELU AU PASSAGE, ET SANS QU'ON L'ATTENDE. La
  /// vignette du sélecteur et celle du tableau de bord viennent de
  /// `cover_photo`, que `owner_venues()` a rendu AVANT que cette salle ait la
  /// moindre photo. Sans cette relecture, le propriétaire verrait un cadre vide
  /// sur une salle qu'il vient d'illustrer. On ne l'attend pas : c'est une
  /// vignette, pas la suite du parcours, et le récapitulatif se lit déjà.
  void _continuer() {
    unawaited(ref.read(espaceProprietaireProvider.notifier).rafraichir());
    context.push(FerhaRoutes.publierRecapitulatifDe(widget.venueId));
  }

  void _quitter() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(FerhaRoutes.proprietaireTableau);
    }
  }

  // ---------------------------------------------------------------------------
  // Construction
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _quitter),
        title: const Text('Photos de la salle'),
      ),
      body: Column(
        children: <Widget>[
          const ProgressionPublication(rang: EtapePublication.rangDesPhotos),
          Expanded(child: _corps()),
          _BarreContinuer(
            manque: _ceQuiManque,
            nombre: _enregistrees.length,
            onContinuer: _continuer,
          ),
        ],
      ),
    );
  }

  Widget _corps() {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    final echec = _echecDeLecture;
    if (echec != null) {
      return EtatErreur(
        titre: 'Vos photos n’ont pas pu être lues',
        erreur: echec,
        onReessayer: _lire,
      );
    }

    return RefreshIndicator(
      onRefresh: _rafraichir,
      child: ListView(
        // `always` : sans lui, une liste trop courte pour défiler ne se laisse
        // pas tirer vers le bas — et c'est justement le cas d'une galerie de
        // deux photos, à qui FE039 et FE040 disent « tirez la liste vers le
        // bas ».
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 24),
        children: <Widget>[
          Text(
            'Ajoutez au moins $photosMinimum photos.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.ferhaColors.inkSecondary,
            ),
          ),
          const SizedBox(height: 16),

          if (_enregistrees.isEmpty && _envois.isEmpty)
            const _GalerieVide()
          else ...<Widget>[
            _liste(),
            const SizedBox(height: 8),
            Text(
              // La phrase de la maquette, mot pour mot : elle dit le geste ET sa
              // conséquence, et c'est la seule explication dont la couverture a
              // besoin — il n'y a pas de bouton « faire de celle-ci la
              // couverture », parce qu'il n'y a pas de couverture à choisir.
              'Maintenez une photo pour la déplacer. La première devient la '
              'couverture.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.ferhaColors.inkTertiary,
              ),
            ),
          ],

          if (_erreur != null) ...<Widget>[
            const SizedBox(height: 16),
            _Refus(message: _erreur!),
          ],

          const SizedBox(height: 20),
          _BoutonsDAjout(
            placesRestantes: _placesRestantes,
            actif: !_ecritureEnCours,
            onAppareilPhoto: _depuisAppareilPhoto,
            onGalerie: _depuisGalerie,
          ),

          const SizedBox(height: 20),
          const _Conseil(),
        ],
      ),
    );
  }

  /// LA LISTE VERTICALE PLUTÔT QUE LA GRILLE DE LA MAQUETTE, et c'est un choix.
  /// Une grille réordonnable demande un paquet ; `ReorderableListView` est dans
  /// Flutter. La maquette donne la structure — des vignettes, la première
  /// marquée « Couverture », qu'on déplace en maintenant le doigt — et cette
  /// structure tient tout entière dans une liste. Une ligne montre d'ailleurs
  /// mieux le rang qu'une grille, et le rang est ce qui compte ici.
  ///
  /// LES ENVOIS EN COURS SONT SOUS LA LISTE, ET NON DEDANS. On ne déplace pas
  /// une photo qui n'a pas encore de ligne en base : elle n'a pas de rang à
  /// échanger, et `reordonner_photos()` refuserait une liste qui la
  /// contiendrait (FE040). Elles rejoignent la liste d'elles-mêmes, en dernier,
  /// dès que la base les accepte.
  Widget _liste() {
    return Column(
      children: <Widget>[
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: !_ecritureEnCours,
          itemCount: _enregistrees.length,
          onReorder: _reordonner,
          itemBuilder: (context, index) {
            final photo = _enregistrees[index];
            return Padding(
              key: ValueKey<String>(photo.id),
              padding: const EdgeInsetsDirectional.only(bottom: 10),
              child: _VignetteEnregistree(
                photo: photo,
                rang: index + 1,
                actif: !_ecritureEnCours,
                onSupprimer: () => _supprimer(photo),
              ),
            );
          },
        ),
        for (final envoi in _envois)
          Padding(
            key: ValueKey<String>(envoi.cle),
            padding: const EdgeInsetsDirectional.only(bottom: 10),
            child: _VignetteEnCours(
              envoi: envoi,
              onRenvoyer: () => _renvoyer(envoi.cle),
              onAbandonner: () => _abandonner(envoi.cle),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Les vignettes
// =============================================================================

/// Une photo déjà en base : son rang, sa pastille de couverture, et sa
/// corbeille.
class _VignetteEnregistree extends StatelessWidget {
  const _VignetteEnregistree({
    required this.photo,
    required this.rang,
    required this.actif,
    required this.onSupprimer,
  });

  final PhotoDeSalle photo;
  final int rang;
  final bool actif;
  final VoidCallback onSupprimer;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return _Cadre(
      enfants: <Widget>[
        _Miniature(child: PhotoSalle(chemin: photo.chemin, tailleIcone: 20)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (photo.estCouverture)
                Container(
                  padding: const EdgeInsetsDirectional.fromSTEB(10, 4, 10, 4),
                  decoration: BoxDecoration(
                    color: colors.primarySoft,
                    borderRadius: FerhaRadii.chipBorder,
                  ),
                  child: Text(
                    'Couverture',
                    style: text.labelSmall?.copyWith(
                      color: colors.primaryDeep,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Text(
                  'Photo $rang',
                  style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
                ),
              const SizedBox(height: 4),
              Text(
                photo.estCouverture
                    // Ce que la couverture EST, dit là où on la regarde : c'est
                    // elle que les familles voient dans les résultats, et c'est
                    // la seule raison de la déplacer.
                    ? 'C’est elle qu’on voit dans les résultats de recherche.'
                    : 'Maintenez pour déplacer.',
                style: text.bodySmall?.copyWith(color: colors.inkTertiary),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: actif ? onSupprimer : null,
          tooltip: 'Supprimer cette photo',
          icon: Icon(Icons.delete_outline, color: colors.inkSecondary),
        ),
      ],
    );
  }
}

/// Une photo en route : sa progression, ou son refus et le bouton qui la
/// renvoie.
class _VignetteEnCours extends StatelessWidget {
  const _VignetteEnCours({
    required this.envoi,
    required this.onRenvoyer,
    required this.onAbandonner,
  });

  final EnvoiDePhoto envoi;
  final VoidCallback onRenvoyer;
  final VoidCallback onAbandonner;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final rate = envoi.etape == EtapeEnvoi.echec;

    return _Cadre(
      enfants: <Widget>[
        _Miniature(
          child: envoi.apercu == null
              ? Container(
                  color: colors.surfaceSecondary,
                  alignment: AlignmentDirectional.center,
                  child: Icon(
                    Icons.image_outlined,
                    size: 20,
                    color: colors.inkTertiary,
                  ),
                )
              : Image.memory(
                  envoi.apercu!,
                  fit: BoxFit.cover,
                  // La vignette fait 72 points de côté : décoder l'image à sa
                  // taille d'affichage plutôt qu'en 1600 px évite de garder
                  // vingt bitmaps entiers en mémoire.
                  cacheWidth: 216,
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                switch (envoi.etape) {
                  EtapeEnvoi.attente => 'En attente…',
                  EtapeEnvoi.compression => 'Préparation…',
                  EtapeEnvoi.envoi => 'Envoi…',
                  EtapeEnvoi.echec => 'Cette photo n’est pas partie',
                },
                style: text.bodyMedium?.copyWith(
                  color: rate ? Theme.of(context).colorScheme.error : null,
                  fontWeight: rate ? FontWeight.w600 : null,
                ),
              ),
              const SizedBox(height: 6),
              if (rate)
                Text(
                  envoi.message ?? 'Réessayez.',
                  style: text.bodySmall?.copyWith(color: colors.inkSecondary),
                )
              else
                ClipRRect(
                  borderRadius: FerhaRadii.chipBorder,
                  child: LinearProgressIndicator(
                    // Indéterminée, et c'est honnête : ni l'encodeur ni
                    // `uploadBinary` ne rendent d'avancement. Une barre qui
                    // afficherait « 40 % » l'inventerait.
                    minHeight: 4,
                    backgroundColor: colors.surfaceSecondary,
                    color: colors.primary,
                  ),
                ),
              if (rate) ...<Widget>[
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    TextButton(
                      onPressed: onRenvoyer,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 8,
                        ),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text('Renvoyer'),
                    ),
                    TextButton(
                      onPressed: onAbandonner,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 8,
                        ),
                        minimumSize: const Size(0, 32),
                        foregroundColor: colors.inkSecondary,
                      ),
                      child: const Text('Retirer'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Le cadre commun aux deux vignettes : même hauteur, même fond, même rayon.
class _Cadre extends StatelessWidget {
  const _Cadre({required this.enfants});

  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Container(
      padding: const EdgeInsetsDirectional.all(10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: FerhaRadii.cardBorder,
        border: Border.all(color: colors.ruleSoft),
      ),
      child: Row(children: enfants),
    );
  }
}

class _Miniature extends StatelessWidget {
  const _Miniature({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: FerhaRadii.imageBorder,
      child: SizedBox(width: 72, height: 72, child: child),
    );
  }
}

// =============================================================================
// Le reste de l'écran
// =============================================================================

class _GalerieVide extends StatelessWidget {
  const _GalerieVide();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(24),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: FerhaRadii.cardBorder,
      ),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.photo_library_outlined,
            size: 32,
            color: colors.inkTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            'Aucune photo pour l’instant',
            style: text.titleSmall?.copyWith(color: colors.ink),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Les photos sont réduites sur votre téléphone avant l’envoi : même '
            'en 4G, cela va vite.',
            style: text.bodySmall?.copyWith(color: colors.inkSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// « Appareil photo » et « Galerie », côte à côte comme sur l'écran 10.
class _BoutonsDAjout extends StatelessWidget {
  const _BoutonsDAjout({
    required this.placesRestantes,
    required this.actif,
    required this.onAppareilPhoto,
    required this.onGalerie,
  });

  final int placesRestantes;
  final bool actif;
  final Future<void> Function() onAppareilPhoto;
  final Future<void> Function() onGalerie;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    // À VINGT PHOTOS, ON N'ÉTEINT PAS DEUX BOUTONS SANS DIRE POURQUOI. La base
    // refuserait la vingt-et-unième (FE038) ; l'écran le dit avant, et dit
    // aussi quoi faire.
    if (placesRestantes <= 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsetsDirectional.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceSecondary,
          borderRadius: FerhaRadii.cardBorder,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.check_circle_outline,
              size: 18,
              color: colors.inkSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Vous avez atteint $photosMaximum photos, le maximum. '
                'Supprimez-en une pour en ajouter une autre.',
                style: text.bodySmall?.copyWith(color: colors.inkSecondary),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            onPressed: actif ? onAppareilPhoto : null,
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: const Text('Appareil photo'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsetsDirectional.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: actif ? onGalerie : null,
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: const Text('Galerie'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsetsDirectional.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

/// Le conseil de l'écran 10 — mais fixe, et sans chiffre inventé.
///
/// La maquette en met un qui se calcule tout seul : « il manque une photo de
/// l'extérieur et une du parking ». Le tenir demanderait de RECONNAÎTRE ce
/// qu'il y a sur les images, ce que le projet ne fait pas et ne fera pas d'ici
/// longtemps. Un conseil faux vaut moins qu'un conseil général : celui-ci dit
/// la même chose, et il est vrai pour toutes les salles.
class _Conseil extends StatelessWidget {
  const _Conseil();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: colors.roseSoft,
        borderRadius: FerhaRadii.cardBorder,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.lightbulb_outline, size: 18, color: colors.roseInk),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Pensez à l’extérieur et au parking.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.roseInk),
            ),
          ),
        ],
      ),
    );
  }
}

/// Le bouton du bas, et ce qui l'empêche de s'allumer.
///
/// Même règle qu'au formulaire : un bouton gris sans explication fait relire
/// l'écran pour trouver ce qui manque. La phrase le dit, et elle est posée
/// au-dessus du bouton, là où le doigt allait.
class _BarreContinuer extends StatelessWidget {
  const _BarreContinuer({
    required this.manque,
    required this.nombre,
    required this.onContinuer,
  });

  final String? manque;
  final int nombre;
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
            Row(
              children: <Widget>[
                Icon(
                  manque == null
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  size: 16,
                  color: colors.inkSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    manque ??
                        (nombre == 1
                            ? '1 photo sur $photosMaximum'
                            : '$nombre photos sur $photosMaximum'),
                    style: text.bodySmall?.copyWith(color: colors.inkSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: manque == null ? onContinuer : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsetsDirectional.symmetric(vertical: 16),
                ),
                child: const Text('Continuer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Le refus de la base, à côté du geste qui l'a produit.
class _Refus extends StatelessWidget {
  const _Refus({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
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
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.ferhaColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
