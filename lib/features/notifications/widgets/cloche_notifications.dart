import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/exiger_connexion.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/ferha_colors.dart';
import '../../../core/theme/ferha_radii.dart';
import '../notifications_providers.dart';

/// La cloche de l'écran 1, et celle du tableau de bord.
///
/// ELLE EST TOUJOURS LÀ, MÊME SANS COMPTE. La maquette la dessine sur un accueil
/// que n'importe qui peut ouvrir, et c'est cohérent avec la règle de navigation
/// du projet : chercher et consulter se font sans compte, la connexion se
/// demande au moment d'agir. Un visiteur voit donc une cloche sans pastille —
/// il n'a rien reçu, ce n'est pas un mensonge — et c'est l'appui qui ouvre la
/// connexion, par `exigerConnexion`.
///
/// LA PASTILLE NE MONTRE PAS UN ZÉRO. « 0 » sur une cloche est une notification
/// de rien : la pastille apparaît à partir de un, et disparaît quand tout est
/// lu. Au-delà de 99, elle dit « 99+ » — le nombre exact n'apprend plus rien et
/// ne tiendrait pas dans le cercle.
class ClocheNotifications extends ConsumerWidget {
  /// Crée la cloche.
  const ClocheNotifications({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nonLues = ref.watch(notificationsNonLuesProvider);

    return IconButton(
      onPressed: () => _ouvrir(context, ref),
      tooltip: nonLues == 0
          ? 'Notifications'
          : 'Notifications — $nonLues non lue${nonLues > 1 ? 's' : ''}',
      icon: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          // La cloche se remplit dès qu'il y a quelque chose à lire : la forme
          // change en même temps que la couleur, pour qui ne distingue pas le
          // rouge du gris.
          Icon(nonLues == 0 ? Icons.notifications_none : Icons.notifications),
          if (nonLues > 0)
            PositionedDirectional(
              top: -3,
              end: -4,
              child: _Pastille(nombre: nonLues),
            ),
        ],
      ),
    );
  }

  Future<void> _ouvrir(BuildContext context, WidgetRef ref) async {
    // Rien à montrer à qui n'est pas connecté, et rien à en dire non plus :
    // `mes_notifications()` ne connaît qu'`auth.uid()`, et rendrait une liste
    // vide qu'on lirait comme « vous n'avez rien reçu ».
    if (!await exigerConnexion(context, ref)) return;
    if (!context.mounted) return;
    context.push(FerhaRoutes.notifications);
  }
}

/// Le petit cercle et son nombre.
class _Pastille extends StatelessWidget {
  const _Pastille({required this.nombre});

  final int nombre;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 5,
        vertical: 1,
      ),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.error,
        shape: BoxShape.rectangle,
        borderRadius: FerhaRadii.chipBorder,
        // Un liseré de la couleur du fond : sans lui, la pastille se confond
        // avec la cloche quand elle la chevauche.
        border: Border.all(color: colors.surface, width: 1.5),
      ),
      child: Text(
        nombre > 99 ? '99+' : '$nombre',
        textAlign: TextAlign.center,
        // Les chiffres restent en écriture latine, y compris en arabe
        // (maquettes, « à prévoir pour l'arabe »).
        textDirection: TextDirection.ltr,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onError,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}
