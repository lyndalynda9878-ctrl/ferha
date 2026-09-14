import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/generated/app_localizations.dart';
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

    // Les textes avant le premier `await` : le contexte peut avoir disparu
    // quand le refus arrive.
    final textes = AppLocalizations.of(context);

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
      setState(() => _erreur = messageErreurAuth(textes, erreur));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  void _afficherConfirmationAttendue() {
    final textes = AppLocalizations.of(context);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(textes.inscriptionVerifiezVotreBoite),
        content: Text(
          textes.inscriptionConfirmationEnvoyee(_email.text.trim()),
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
            child: Text(textes.inscriptionAllerALaConnexion),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final textes = AppLocalizations.of(context);

    return AuthScaffold(
      titre: textes.authCreerUnCompte,
      sousTitre: textes.inscriptionSousTitre,
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
                decoration: InputDecoration(
                  labelText: textes.inscriptionNomComplet,
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
                validator: (valeur) {
                  final nom = valeur?.trim() ?? '';
                  if (nom.isEmpty) return textes.inscriptionNomManquant;
                  if (nom.length < 2) return textes.inscriptionNomTropCourt;
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
                decoration: InputDecoration(
                  labelText: textes.authAdresseEmail,
                  prefixIcon: const Icon(Icons.alternate_email),
                ),
                validator: (valeur) => validerEmail(textes, valeur),
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
                  labelText: textes.authMotDePasse,
                  helperText: textes.inscriptionSixCaracteres,
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
                    tooltip: _motDePasseVisible
                        ? textes.authMasquer
                        : textes.authAfficher,
                  ),
                ),
                validator: (valeur) {
                  final motDePasse = valeur ?? '';
                  if (motDePasse.isEmpty) {
                    return textes.inscriptionMotDePasseManquant;
                  }
                  // Six caractères est le minimum de Supabase. On le vérifie
                  // ici pour ne pas faire un aller-retour réseau qui dirait la
                  // même chose — et c'est la MÊME phrase que le texte d'aide
                  // au-dessus du champ, parce que c'est la même règle.
                  if (motDePasse.length < 6) {
                    return textes.inscriptionSixCaracteres;
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
                      : Text(textes.inscriptionCreerMonCompte),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        Text(
          textes.inscriptionEspaceProprietaire,
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: colors.inkTertiary),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _enCours ? null : () => context.go(FerhaRoutes.connexion),
          child: Text(textes.inscriptionDejaUnCompte),
        ),
      ],
    );
  }
}
