import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../supabase/session_providers.dart';
import 'routes.dart';

/// Demande la connexion, mais seulement au moment d'agir.
///
/// C'EST LA RÈGLE DE NAVIGATION DU PROJET, et elle tient en une phrase : un
/// visiteur non connecté peut chercher une salle, ouvrir une fiche, regarder
/// un calendrier et lire les avis. La connexion n'est réclamée qu'au moment
/// où il veut *faire* quelque chose — envoyer une demande, écrire à un
/// propriétaire, déposer un avis.
///
/// C'est pourquoi le routeur n'a **aucune redirection globale** vers la
/// connexion. Une redirection posée sur des routes de consultation
/// transformerait l'application en annuaire fermé : on ne demande pas sa carte
/// d'identité à quelqu'un qui regarde une vitrine.
///
/// Usage, depuis l'écran qui porte le geste :
///
/// ```dart
/// if (!await exigerConnexion(context, ref)) return;
/// // ... ici, la session existe
/// ```
///
/// Renvoie `true` si la session existe déjà — l'appel est alors gratuit et le
/// geste continue sans que rien ne s'affiche. Sinon, ouvre l'écran de
/// connexion par-dessus l'écran courant et renvoie `false` : le geste est
/// abandonné, pas mis en attente. Une fois connecté, le client revient sur la
/// route [retour] (par défaut celle d'où il vient) et refait son geste — cette
/// fois, en une seule étape.
Future<bool> exigerConnexion(
  BuildContext context,
  WidgetRef ref, {
  String? retour,
}) async {
  if (ref.read(estConnecteProvider)) return true;

  final destination = retour ?? GoRouterState.of(context).uri.toString();

  await context.push<void>(
    Uri(
      path: FerhaRoutes.connexion,
      queryParameters: <String, String>{
        FerhaRoutes.parametreRetour: destination,
      },
    ).toString(),
  );

  // L'écran de connexion s'est refermé : soit la session existe maintenant,
  // soit le visiteur a renoncé. On ne rejoue pas le geste à sa place.
  return context.mounted && ref.read(estConnecteProvider);
}
