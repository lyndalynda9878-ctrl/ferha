import 'package:flutter/material.dart';

import '../../../core/theme/ferha_colors.dart';
import '../../../core/theme/ferha_radii.dart';

/// Coque commune aux écrans de connexion et d'inscription.
///
/// Elle tient la mise en page : centrée, bornée en largeur pour rester lisible
/// sur un écran d'ordinateur, et défilante pour que le clavier d'un téléphone
/// ne recouvre jamais le champ actif.
class AuthScaffold extends StatelessWidget {
  /// Crée la coque d'un écran d'authentification.
  const AuthScaffold({
    required this.titre,
    required this.sousTitre,
    required this.children,
    super.key,
  });

  /// Titre de l'écran.
  final String titre;

  /// Une phrase qui dit à quoi sert l'écran.
  final String sousTitre;

  /// Le formulaire et ses boutons.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(titre, style: text.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    sousTitre,
                    style: text.bodyMedium?.copyWith(
                      color: colors.inkSecondary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bandeau d'erreur, affiché au-dessus d'un formulaire.
///
/// Il porte le message traduit par `messageErreurAuth`, jamais le texte brut
/// d'une exception.
class AuthErreur extends StatelessWidget {
  /// Crée le bandeau d'erreur.
  const AuthErreur({required this.message, super.key});

  /// Le message, déjà traduit et déjà en français.
  final String message;

  @override
  Widget build(BuildContext context) {
    final erreur = Theme.of(context).colorScheme.error;
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsetsDirectional.only(bottom: 20),
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: FerhaRadii.cardBorder,
        border: Border.all(color: erreur),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 1, end: 10),
            child: Icon(Icons.error_outline, size: 20, color: erreur),
          ),
          Expanded(
            child: Text(
              message,
              style: text.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
