import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/ferha_colors.dart';
import '../../core/theme/ferha_radii.dart';
import '../search/search_filters.dart';
import '../search/widgets/etats.dart';
import 'notification_ferha.dart';
import 'notifications_providers.dart';
import 'notifications_repository.dart';

/// L'écran des notifications (§4.1, CORE-04).
///
/// IL NE CHARGE RIEN LUI-MÊME, ET C'EST VOULU. La liste vit dans
/// [notificationsProvider], qui se charge à l'ouverture ET écoute le temps réel
/// — la cloche en a besoin depuis l'accueil, bien avant que cet écran existe.
/// Un chargement propre à l'écran ferait une seconde source pour le même
/// nombre, et deux sources finissent toujours par diverger.
///
/// LES NON LUES SE VOIENT SANS SE COMPTER. Une pastille en début de ligne, un
/// fond légèrement teinté, un titre en gras : trois marques plutôt qu'une,
/// parce qu'une seule couleur ne se voit pas de tout le monde.
///
/// TOUCHER UNE NOTIFICATION FAIT DEUX CHOSES, dans cet ordre : elle s'éteint,
/// puis l'écran s'ouvre. L'inverse — ouvrir, puis marquer — laisserait la
/// pastille allumée le temps de la transition, et on croirait avoir mal appuyé.
class NotificationsScreen extends ConsumerWidget {
  /// Crée l'écran.
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(notificationsProvider);
    final nonLues = liste.value?.nonLues ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: <Widget>[
          // Le bouton n'apparaît QUE s'il a quelque chose à faire. Un « Tout
          // marquer comme lu » grisé en permanence occupe la barre sans jamais
          // servir.
          if (nonLues > 0)
            TextButton(
              onPressed: () => _toutMarquerLu(context, ref),
              child: const Text('Tout marquer comme lu'),
            ),
        ],
      ),
      body: switch (liste) {
        AsyncError(:final error) => EtatErreur(
          titre: 'Vos notifications n’ont pas pu être lues',
          erreur: error,
          onReessayer: () =>
              ref.read(notificationsProvider.notifier).reessayer(),
        ),
        AsyncData(:final value) when value.items.isEmpty => const _Aucune(),
        AsyncData(:final value) => _Liste(liste: value),
        _ => const _Squelette(),
      },
    );
  }

  Future<void> _toutMarquerLu(BuildContext context, WidgetRef ref) async {
    final messages = ScaffoldMessenger.of(context);
    try {
      await ref.read(notificationsProvider.notifier).toutMarquerLu();
    } on Object catch (_) {
      // Celui-là, on est venu le faire : un échec muet laisserait croire que
      // c'est passé, et les pastilles se rallumeraient au prochain retour.
      messages.showSnackBar(
        const SnackBar(
          content: Text('Les notifications n’ont pas pu être marquées lues.'),
        ),
      );
    }
  }
}

class _Liste extends StatelessWidget {
  const _Liste({required this.liste});

  final ListeNotifications liste;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return ListView.separated(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 8, 0, 32),
      itemCount: liste.items.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, indent: 20, color: colors.ruleSoft),
      itemBuilder: (context, i) => _Ligne(
        notification: liste.items[i],
        key: ValueKey<String>(liste.items[i].id),
      ),
    );
  }
}

/// Une notification : sa pastille, son titre, sa salle, son âge.
class _Ligne extends ConsumerWidget {
  const _Ligne({required this.notification, super.key});

  final NotificationFerha notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final lue = notification.lue;

    return Material(
      // Le fond de l'écran quand elle est lue, un ambre très pâle sinon : la
      // teinte est l'une des trois marques du non-lu, avec la pastille et la
      // graisse du titre. Trois plutôt qu'une, parce qu'une seule couleur ne se
      // voit pas de tout le monde.
      color: lue ? colors.background : colors.primarySoft,
      child: InkWell(
        onTap: () => _ouvrir(context, ref),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Point(allume: !lue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      notification.titre,
                      style: text.titleSmall?.copyWith(
                        fontWeight: lue ? FontWeight.w500 : FontWeight.w700,
                        color: colors.ink,
                      ),
                    ),
                    // La ligne de détail vient du payload — salle, date,
                    // créneau. Elle peut être vide : une notification sans
                    // réservation rattachée n'invente pas de texte.
                    if (notification.details.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        notification.details,
                        style: text.bodySmall?.copyWith(
                          color: colors.inkSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Text(
                      ilYA(notification.creeLe),
                      style: text.labelSmall?.copyWith(
                        color: colors.inkTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                // L'icône directionnelle se retourne en arabe ; les autres non
                // (maquettes, « à prévoir pour l'arabe »).
                Icons.chevron_right,
                size: 20,
                color: colors.inkTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _ouvrir(BuildContext context, WidgetRef ref) async {
    final destination = notification.destination;
    // Marquer d'abord : l'appel est optimiste et ne se fait pas attendre.
    await ref.read(notificationsProvider.notifier).marquerLue(notification.id);
    if (!context.mounted) return;
    context.push(destination);
  }
}

/// La pastille de tête : pleine quand la notification n'est pas lue.
///
/// Elle garde sa place une fois éteinte — sinon tout le texte se décalerait à
/// la lecture, et la liste bougerait sous le doigt.
class _Point extends StatelessWidget {
  const _Point({required this.allume});

  final bool allume;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 6),
      child: SizedBox(
        width: 10,
        height: 10,
        child: allume
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
              )
            : null,
      ),
    );
  }
}

class _Aucune extends StatelessWidget {
  const _Aucune();

  @override
  Widget build(BuildContext context) {
    return const EtatVide(
      icone: Icons.notifications_none,
      titre: 'Aucune notification',
      explication:
          'Vous serez prévenu ici dès qu’une demande avance : une réponse du '
          'propriétaire, un acompte reçu, une option qui arrive à échéance.',
    );
  }
}

/// Des lignes à la forme de celles qui arrivent.
class _Squelette extends StatelessWidget {
  const _Squelette();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return ListView.separated(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 32),
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(height: 22),
      itemBuilder: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Barre(largeur: 220, hauteur: 14, couleur: colors.surfaceSecondary),
          const SizedBox(height: 8),
          _Barre(largeur: 160, hauteur: 11, couleur: colors.surfaceSecondary),
        ],
      ),
    );
  }
}

class _Barre extends StatelessWidget {
  const _Barre({
    required this.largeur,
    required this.hauteur,
    required this.couleur,
  });

  final double largeur;
  final double hauteur;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: largeur,
      height: hauteur,
      decoration: BoxDecoration(
        color: couleur,
        borderRadius: FerhaRadii.chipBorder,
      ),
    );
  }
}

/// « à l'instant », « il y a 2 h », « il y a 3 jours », puis la date.
///
/// ÉCRIT ICI PLUTÔT QUE TIRÉ D'`intl`, comme les douze mois de
/// `search_filters.dart` : le paquet n'est qu'une dépendance transitive, et
/// cinq phrases ne valent pas une dépendance de plus.
///
/// AU-DELÀ D'UNE SEMAINE, ON DONNE LA DATE. « Il y a 34 jours » oblige à faire
/// la soustraction soi-même pour savoir de quand il s'agit.
String ilYA(DateTime quand, {DateTime? maintenant}) {
  final ecart = (maintenant ?? DateTime.now()).difference(quand);

  if (ecart.inMinutes < 1) return 'à l’instant';
  if (ecart.inMinutes < 60) return 'il y a ${ecart.inMinutes} min';
  if (ecart.inHours < 24) return 'il y a ${ecart.inHours} h';
  if (ecart.inDays == 1) return 'hier';
  if (ecart.inDays < 7) return 'il y a ${ecart.inDays} jours';
  return dateEnFrancais(quand);
}
