import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/preferences/preferences_affichage.dart';
import '../auth/auth_providers.dart';
import '../search/search_filters.dart';
import 'creneau_agenda.dart';
import 'demande_detail.dart';
import 'demande_en_attente.dart';
import 'indicateurs_salle.dart';
import 'nouvelle_salle.dart';
import 'owner_repository.dart';
import 'salle_du_proprietaire.dart';

/// Les salles d'un propriétaire, et celle qu'il regarde.
///
/// LES DEUX VONT ENSEMBLE, ET C'EST POURQUOI C'EST UN SEUL ÉTAT. Une salle
/// courante rangée à part pourrait désigner une salle absente de la liste — au
/// mieux un écran vide, au pire un appel à `owner_dashboard()` sur la salle
/// d'un autre. Ici, [salleCourante] se lit DANS [salles] : les deux ne peuvent
/// pas diverger.
@immutable
class EspaceProprietaire {
  /// Crée l'état de l'espace propriétaire.
  const EspaceProprietaire({required this.salles, this.salleCouranteId});

  /// Toutes les salles du propriétaire, brouillons compris, par nom.
  final List<SalleDuProprietaire> salles;

  /// L'identifiant de la salle affichée, ou `null` s'il n'en a aucune.
  final String? salleCouranteId;

  /// La salle affichée.
  ///
  /// `null` seulement quand la liste est vide : [EspaceProprietaireNotifier]
  /// ne retient jamais un identifiant absent de [salles].
  SalleDuProprietaire? get salleCourante {
    for (final salle in salles) {
      if (salle.id == salleCouranteId) return salle;
    }
    return null;
  }

  /// Vrai quand il y a plusieurs salles, donc un choix à offrir (OWN-08).
  bool get plusieursSalles => salles.length > 1;
}

/// Charge les salles du propriétaire et retrouve celle qu'il regardait.
///
/// POURQUOI RETENIR LA SALLE. Karim en a quatre, et il ouvre son tableau de
/// bord plusieurs fois par jour pour la même. La lui redemander à chaque fois
/// serait lui faire payer un choix qu'il a déjà fait — et lui faire croire, la
/// première seconde, que ses chiffres sont ceux d'une autre salle.
///
/// LA PRÉFÉRENCE N'EST PAS UNE AUTORISATION. L'identifiant retenu vient d'un
/// fichier en clair sur l'appareil, que n'importe qui peut réécrire ; il n'est
/// donc jamais cru sur parole. On ne garde une salle retenue que si elle est
/// dans la liste que la BASE vient de rendre — et cette liste-là ne contient
/// que les salles du propriétaire connecté, `owner_venues()` ne connaissant
/// qu'`auth.uid()`. Une préférence rescapée d'un autre compte, ou pointant une
/// salle vendue depuis, ne fait donc rien d'autre que se faire oublier.
class EspaceProprietaireNotifier extends AsyncNotifier<EspaceProprietaire> {
  @override
  Future<EspaceProprietaire> build() async {
    // Se déconnecter vide l'espace, se connecter le recharge : aucun écran n'a
    // à s'en occuper.
    //
    // On observe le BOOLÉEN et non la session elle-même. La session change
    // aussi à chaque renouvellement de jeton — toutes les heures, sans que rien
    // n'ait bougé pour le propriétaire ; la suivre ferait redemander la liste
    // des salles à chacun. Ce qui compte ici est le passage de « personne » à
    // « quelqu'un », et c'est exactement ce que ce booléen dit.
    if (!ref.watch(estConnecteProvider)) {
      return const EspaceProprietaire(salles: <SalleDuProprietaire>[]);
    }

    final salles = await ref.read(ownerRepositoryProvider).salles();
    if (salles.isEmpty) {
      return const EspaceProprietaire(salles: <SalleDuProprietaire>[]);
    }

    final preferences = ref.read(preferencesAffichageProvider);
    final retenue = await preferences.salleChoisie();
    final existe = salles.any((s) => s.id == retenue);
    final courante = existe ? retenue! : salles.first.id;

    // La préférence ne survit pas à la salle qu'elle désigne. La réécrire ici
    // évite qu'un identifiant mort reste sur l'appareil à être réexaminé à
    // chaque ouverture ; on n'écrit que si elle a bougé, parce qu'une écriture
    // par démarrage pour reposer la même valeur ne sert personne.
    if (retenue != courante) await preferences.retenirSalle(courante);

    return EspaceProprietaire(salles: salles, salleCouranteId: courante);
  }

  /// Change de salle, et le retient pour la prochaine ouverture.
  ///
  /// L'écran change AVANT que l'appareil ait fini d'écrire : le sélecteur doit
  /// se refermer sur les chiffres de la nouvelle salle, pas attendre un accès
  /// disque. Une écriture ratée ne coûte alors qu'un choix oublié au prochain
  /// démarrage — jamais un tableau de bord qui refuse de tourner.
  Future<void> choisir(String venueId) async {
    final actuel = state.value;
    if (actuel == null || actuel.salleCouranteId == venueId) return;
    if (!actuel.salles.any((s) => s.id == venueId)) return;

    state = AsyncData<EspaceProprietaire>(
      EspaceProprietaire(salles: actuel.salles, salleCouranteId: venueId),
    );
    await ref.read(preferencesAffichageProvider).retenirSalle(venueId);
  }

  /// Relit la liste des salles, squelette compris — le bouton « Réessayer ».
  Future<void> reessayer() async {
    state = const AsyncLoading<EspaceProprietaire>();
    state = await AsyncValue.guard(build);
  }

  /// Relit les salles SANS repasser par un état de chargement.
  ///
  /// Appelée après une réponse à une demande : le compte du sélecteur — « Salle
  /// El Bahia · 3 » — vient d'`owner_venues()`, et il devient faux à la seconde
  /// où le propriétaire accepte ou refuse.
  ///
  /// POURQUOI PAS `ref.invalidate()`. Un fournisseur invalidé repasse par
  /// `AsyncLoading`, et le tableau de bord retomberait sur son squelette une
  /// demi-seconde après chaque réponse — nom de la salle compris, puisqu'il est
  /// le titre. On recharge donc les données sans toucher à l'enveloppe, comme
  /// le suivi client le fait à chaque événement Realtime.
  ///
  /// Un échec ici ne casse rien et ne se dit pas : les chiffres qui comptent
  /// sont ailleurs, et le compteur sera juste à la prochaine ouverture.
  Future<void> rafraichir() async {
    final actuel = state.value;
    if (actuel == null || actuel.salles.isEmpty) return;

    try {
      final salles = await ref.read(ownerRepositoryProvider).salles();
      if (!ref.mounted) return;

      // La salle regardée ne change pas parce qu'on a répondu à une demande —
      // sauf si elle vient de disparaître de la liste, auquel cas on retombe
      // sur la première, comme au démarrage.
      final couranteExiste = salles.any((s) => s.id == actuel.salleCouranteId);
      state = AsyncData<EspaceProprietaire>(
        EspaceProprietaire(
          salles: salles,
          salleCouranteId: couranteExiste
              ? actuel.salleCouranteId
              : (salles.isEmpty ? null : salles.first.id),
        ),
      );
    } on Object catch (_) {
      // Volontairement muet, voir ci-dessus.
    }
  }
}

/// Les salles du propriétaire connecté, et celle qu'il regarde.
final espaceProprietaireProvider =
    AsyncNotifierProvider<EspaceProprietaireNotifier, EspaceProprietaire>(
      EspaceProprietaireNotifier.new,
    );

/// Les indicateurs du mois en cours pour une salle (§4.3, OWN-07).
///
/// Une famille indexée sur la salle, et non un fournisseur unique : changer de
/// salle dans le sélecteur redemande alors les chiffres tout seul, et revenir
/// à la précédente les retrouve. `autoDispose` referme ce qui n'est plus
/// regardé — Karim a quatre salles, il n'en voit qu'une à la fois.
final indicateursProvider = FutureProvider.autoDispose
    .family<IndicateursSalle, String>(
      (ref, venueId) => ref.watch(ownerRepositoryProvider).indicateurs(venueId),
    );

/// Le détail d'une demande (§4.3, OWN-05).
///
/// Indexé sur la demande et non sur la salle : on en ouvre une à la fois, et
/// `autoDispose` referme celle qu'on vient de quitter.
final detailDemandeProvider = FutureProvider.autoDispose
    .family<DemandeDetail, String>(
      (ref, bookingId) => ref.watch(ownerRepositoryProvider).detail(bookingId),
    );

/// Les demandes en attente d'une salle (§4.3, OWN-05).
///
/// PAS D'ABONNEMENT TEMPS RÉEL ICI, à la différence du suivi côté client. Là-bas
/// l'écran répond à « où en est ma demande » et attend un événement qu'il ne
/// provoque pas ; ici, c'est le propriétaire lui-même qui fait bouger la liste
/// en répondant — et les gestes qui la feront bouger n'existent pas encore.
/// L'écran se retire vers le bas pour se rafraîchir, ce qui suffit tant que
/// personne d'autre n'écrit à sa place.
final demandesEnAttenteProvider = FutureProvider.autoDispose
    .family<List<DemandeEnAttente>, String>(
      (ref, venueId) =>
          ref.watch(ownerRepositoryProvider).demandesEnAttente(venueId),
    );

/// Répondre à une demande, et remettre d'aplomb tout ce que la réponse fausse.
///
/// LE POINT DE CETTE CLASSE EST LA SECONDE MOITIÉ. Appeler `accepter_demande()`
/// est une ligne ; ce qui se casse ensuite si l'on s'arrête là est moins
/// visible. Une demande acceptée quitte la file, mais le compte du sélecteur
/// vient d'`owner_venues()`, la file elle-même de `owner_pending_requests()`,
/// et la part acceptée du mois d'`owner_dashboard()` — trois lectures qui
/// ignorent tout de ce qui vient de se passer. Le propriétaire, lui, verrait
/// « 3 demandes » sur un tableau qui n'en montre plus que deux, et croirait
/// qu'il en a perdu une.
///
/// AUCUNE VÉRIFICATION DE DROIT ICI. Les deux fonctions de 015 refusent
/// elles-mêmes une demande qui n'est pas la vôtre, et c'est ce refus-là qui
/// protège. Ce service ne fait que transporter, puis ranger derrière lui.
class ReponseADemandeService {
  /// Crée le service.
  const ReponseADemandeService(this._ref);

  final Ref _ref;

  /// Accepte la demande : elle passe en option de 72 h (§5.1).
  Future<void> accepter(DemandeDetail demande) async {
    await _ref.read(ownerRepositoryProvider).accepter(demande.bookingId);
    await _rafraichir(demande);
  }

  /// Refuse la demande. Le motif est facultatif — la base l'accepte vide.
  Future<void> refuser(DemandeDetail demande, {String? motif}) async {
    await _ref
        .read(ownerRepositoryProvider)
        .refuser(demande.bookingId, motif: motif);
    await _rafraichir(demande);
  }

  /// Ce que la réponse vient de rendre faux, et rien d'autre.
  Future<void> _rafraichir(DemandeDetail demande) async {
    // Le détail lui-même : l'écran doit montrer le nouvel état, l'acompte fixé
    // et l'échéance des 72 h, qu'il n'avait pas une seconde plus tôt.
    _ref.invalidate(detailDemandeProvider(demande.bookingId));
    _ref.invalidate(demandesEnAttenteProvider(demande.venueId));
    // La part des demandes acceptées du mois a bougé, et le nombre de demandes
    // tranchées avec elle.
    _ref.invalidate(indicateursProvider(demande.venueId));

    // Le compte du sélecteur. Rechargé et non invalidé — voir `rafraichir()`.
    await _ref.read(espaceProprietaireProvider.notifier).rafraichir();
  }
}

/// Le service de réponse aux demandes.
final reponseADemandeServiceProvider = Provider<ReponseADemandeService>(
  ReponseADemandeService.new,
);

/// Vrai quand la salle regardée est une salle du propriétaire connecté.
///
/// C'EST UNE QUESTION D'AFFICHAGE, PAS UN DROIT. Ce qui protège reste
/// `request_booking()`, qui refuse elle-même une demande d'un propriétaire sur
/// sa propre salle (FE005, migration 012). Ce fournisseur ne sert qu'à ne pas
/// PROPOSER un geste qu'on sait perdu d'avance : mieux vaut ne pas mettre la
/// porte que de la barrer au dernier moment.
///
/// LA LISTE EST CELLE DE LA BASE, PAS UNE DÉDUCTION. `owner_venues()` ne
/// connaît qu'`auth.uid()` : un visiteur non connecté n'appelle rien du tout —
/// [EspaceProprietaireNotifier] s'arrête sur la liste vide — et un client
/// connecté qui ne possède rien reçoit une liste vide. La fiche salle ne révèle
/// donc toujours RIEN du propriétaire (§9) : c'est le lecteur qui dit ce qu'il
/// possède, jamais la salle qui dit à qui elle est.
///
/// TANT QUE LA LISTE CHARGE, ON RÉPOND « NON ». C'est le mauvais côté d'une
/// image ou deux — le bouton client, puis le bouton propriétaire — plutôt que
/// l'inverse, qui montrerait « Gérer ma salle » une fraction de seconde à
/// quelqu'un qui n'a jamais eu de salle. Un faux non se corrige tout seul ; un
/// faux oui laisserait un souvenir.
final estMaSalleProvider = Provider.family<bool, String>((ref, venueId) {
  final espace = ref.watch(espaceProprietaireProvider).value;
  return espace != null && espace.salles.any((s) => s.id == venueId);
});

/// L'agenda d'une salle sur un mois (§4.3, OWN-06).
///
/// Une famille indexée sur la salle ET le mois, comme les indicateurs le sont
/// sur la salle : feuilleter vers août puis revenir à juillet retrouve juillet
/// sans le redemander. `autoDispose` referme les mois qu'on a quittés — on en
/// regarde un à la fois, et dix-huit mois gardés en mémoire ne serviraient à
/// personne.
///
/// UN APPEL PAR MOIS, PAS PAR CRÉNEAU. `owner_agenda()` rend midi ET soir en une
/// fois : la bascule midi/soir de l'écran ne touche donc pas au réseau, elle
/// relit ce qui est déjà là. C'est la différence avec le calendrier client, qui
/// a un fournisseur par créneau parce que sa fonction SQL n'en rend qu'un.
final agendaProvider = FutureProvider.autoDispose
    .family<AgendaDuMois, DemandeAgenda>(
      (ref, demande) => ref
          .watch(ownerRepositoryProvider)
          .agenda(demande.venueId, demande.mois),
    );

/// Fermer une date, la rouvrir, et remettre d'aplomb ce que le geste fausse.
///
/// MÊME PARTAGE DES RÔLES QUE [ReponseADemandeService] : la fonction SQL fait le
/// travail et porte le garde-fou, ce service transporte puis range derrière lui.
/// Aucune vérification de propriété ici — `bloquer_date()` et
/// `debloquer_date()` (016) refusent d'elles-mêmes la salle d'un autre, et c'est
/// ce refus-là qui protège.
///
/// CE QU'IL FAUT RANGER APRÈS COUP est plus large que le mois touché. Fermer un
/// créneau change le dénominateur du taux d'occupation — `owner_dashboard()`
/// compte les créneaux VENDABLES, soit deux par jour moins les blocages —, et
/// une semaine fermée ne doit pas faire chuter le taux. L'indicateur est donc
/// relu, sans quoi le propriétaire verrait ses chiffres mentir jusqu'à la
/// prochaine ouverture.
class FermetureDeDateService {
  /// Crée le service.
  const FermetureDeDateService(this._ref);

  final Ref _ref;

  /// Ferme un créneau, avec un motif facultatif.
  Future<void> fermer(
    String venueId,
    DateTime jour,
    Creneau creneau, {
    String? motif,
  }) async {
    await _ref
        .read(ownerRepositoryProvider)
        .bloquer(venueId, jour, creneau, motif: motif);
    _rafraichir(venueId, jour);
  }

  /// Rouvre un créneau fermé.
  Future<void> rouvrir(String venueId, DateTime jour, Creneau creneau) async {
    await _ref.read(ownerRepositoryProvider).debloquer(venueId, jour, creneau);
    _rafraichir(venueId, jour);
  }

  void _rafraichir(String venueId, DateTime jour) {
    _ref.invalidate(
      agendaProvider(DemandeAgenda(venueId: venueId, mois: jour)),
    );
    // Le taux d'occupation du tableau de bord compte les créneaux vendables :
    // il vient de changer.
    _ref.invalidate(indicateursProvider(venueId));
  }
}

/// Le service de fermeture de dates.
final fermetureDeDateServiceProvider = Provider<FermetureDeDateService>(
  FermetureDeDateService.new,
);

/// Inscrire une salle, puis l'envoyer à la validation (§4.3, OWN-01).
///
/// DEUX GESTES, ET LE PREMIER OUVRE LA PORTE DU SECOND. `creerSalle()` rend un
/// identifiant : c'est lui qui mène au récapitulatif, et c'est lui dont les
/// photos auront besoin pour leur chemin de Storage. Entre les deux, la salle
/// existe en brouillon et n'est visible de personne — ni du catalogue, ni de la
/// recherche.
///
/// AUCUNE VÉRIFICATION DE DROIT ICI, comme pour les autres services de ce
/// dossier. `creer_salle()` lit `auth.uid()` et `envoyer_salle_en_validation()`
/// refuse la salle d'un autre (FE034) ; ce service ne fait que transporter,
/// puis ranger derrière lui.
class PublicationDeSalleService {
  /// Crée le service.
  const PublicationDeSalleService(this._ref);

  final Ref _ref;

  /// Inscrit la salle en brouillon, et rend son identifiant.
  ///
  /// L'ESPACE PROPRIÉTAIRE EST RECHARGÉ DERRIÈRE, et c'est la moitié du travail
  /// de cette méthode. Une cliente qui vient d'inscrire sa salle n'était pas
  /// propriétaire une seconde plus tôt : `owner_venues()` lui rendait une liste
  /// vide, et `espaceProprietaireProvider` la garde en mémoire. Sans ce
  /// rechargement, son tableau de bord dirait « vous n'avez aucune salle » sur
  /// une salle qu'elle vient de créer. Le profil est relu pour la même raison :
  /// c'est `is_owner` qui décide de l'entrée de l'espace propriétaire, et il
  /// vient de passer à vrai.
  Future<String> creer(NouvelleSalle salle) async {
    final venueId = await _ref.read(ownerRepositoryProvider).creerSalle(salle);

    _ref.invalidate(profilProvider);
    await _ref.read(espaceProprietaireProvider.notifier).reessayer();

    return venueId;
  }

  /// Envoie le brouillon à la validation humaine (ADM-01).
  ///
  /// Le statut de la salle change, et c'est lui que le sélecteur et le bandeau
  /// du tableau de bord affichent — « Brouillon » devient « En attente de
  /// validation ». On recharge donc la liste, sans repasser par un squelette.
  Future<void> envoyer(String venueId) async {
    await _ref.read(ownerRepositoryProvider).envoyerEnValidation(venueId);
    await _ref.read(espaceProprietaireProvider.notifier).rafraichir();
  }
}

/// Le service de publication d'une salle.
final publicationDeSalleServiceProvider = Provider<PublicationDeSalleService>(
  PublicationDeSalleService.new,
);
