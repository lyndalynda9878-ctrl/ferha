import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/locale_controller.dart';
import '../../core/router/routes.dart';
import '../../core/theme/ferha_colors.dart';
import 'auth_messages.dart';
import 'auth_service.dart';
import 'connexion_screen.dart' show validerEmail;
import 'widgets/auth_scaffold.dart';

/// Écran de création de compte (§4.1, CORE-01).
///
/// Trois champs, pas quatre : nom, e-mail, mot de passe. Le téléphone est
/// devenu un champ de profil en v2.0 — il se renseigne plus tard, depuis
/// l'écran de profil, et n'a pas à retarder une inscription.
class InscriptionScreen extends ConsumerStatefulWidget {
  /// Crée l'écran de création de compte.
  const InscriptionScreen({super.key});

  @override
  ConsumerState<InscriptionScreen> createState() => _InscriptionScreenState();
}

class _InscriptionScreenState extends ConsumerState<InscriptionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nom = TextEditingController();
  final _email = TextEditingController();
  final _motDePasse = TextEditingController();

  bool _enCours = false;
  bool _motDePasseVisible = false;
  String? _erreur;

  @override
  void dispose() {
    _nom.dispose();
    _email.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  Future<void> _sInscrire() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      // Selon le réglage « Confirm email » du projet Supabase, l'inscription
      // ouvre une session tout de suite, ou attend un clic dans un e-mail.
      // C'est la réponse du serveur qui le dit, pas une supposition.
      final connecte = await ref
          .read(authServiceProvider)
          .inscription(
            email: _email.text,
            motDePasse: _motDePasse.text,
            nomComplet: _nom.text,
            locale: ref.read(localeProvider).languageCode,
          );
      if (!mounted) return;

      if (connecte) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(FerhaRoutes.profil);
        }
      } else {
        _afficherConfirmationAttendue();
      }
    } on Object catch (erreur) {
      if (!mounted) return;
      setState(() => _erreur = messageErreurAuth(erreur));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  void _afficherConfirmationAttendue() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vérifiez votre boîte mail'),
        content: Text(
          'Un message vient d’être envoyé à ${_email.text.trim()}. '
          'Ouvrez-le pour confirmer votre adresse, puis connectez-vous.',
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () {
              // On ferme la boîte de dialogue, puis l'écran d'inscription.
              // On revient ainsi sur la connexion si c'est de là qu'on vient.
              Navigator.of(context).pop();
              final routeur = GoRouter.of(context);
              if (routeur.canPop()) {
                routeur.pop();
              } else {
                routeur.go(FerhaRoutes.connexion);
              }
            },
            child: const Text('Aller à la connexion'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return AuthScaffold(
      titre: 'Créer un compte',
      sousTitre:
          'Quelques secondes suffisent. Vous pourrez chercher une salle '
          'sans compte, mais il en faut un pour envoyer une demande.',
      children: <Widget>[
        if (_erreur != null) AuthErreur(message: _erreur!),

        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                controller: _nom,
                enabled: !_enCours,
                textCapitalization: TextCapitalization.words,
                autofillHints: const <String>[AutofillHints.name],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nom complet',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (valeur) {
                  final nom = valeur?.trim() ?? '';
                  if (nom.isEmpty) return 'Entrez votre nom.';
                  if (nom.length < 2) return 'Ce nom est trop court.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                enabled: !_enCours,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const <String>[AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Adresse e-mail',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                validator: validerEmail,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _motDePasse,
                enabled: !_enCours,
                obscureText: !_motDePasseVisible,
                autofillHints: const <String>[AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _sInscrire(),
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  helperText: 'Six caractères au minimum.',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () => setState(
                      () => _motDePasseVisible = !_motDePasseVisible,
                    ),
                    icon: Icon(
                      _motDePasseVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    tooltip: _motDePasseVisible ? 'Masquer' : 'Afficher',
                  ),
                ),
                validator: (valeur) {
                  final motDePasse = valeur ?? '';
                  if (motDePasse.isEmpty) return 'Choisissez un mot de passe.';
                  // Six caractères est le minimum de Supabase. On le vérifie
                  // ici pour ne pas faire un aller-retour réseau qui dirait la
                  // même chose.
                  if (motDePasse.length < 6) {
                    return 'Six caractères au minimum.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _enCours ? null : _sInscrire,
                  child: _enCours
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        )
                      : const Text('Créer mon compte'),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        Text(
          'Vous pourrez ouvrir votre espace propriétaire plus tard, depuis '
          'votre profil.',
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: colors.inkTertiary),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _enCours ? null : () => context.go(FerhaRoutes.connexion),
          child: const Text('J’ai déjà un compte'),
        ),
      ],
    );
  }
}
