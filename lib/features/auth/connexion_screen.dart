import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/ferha_colors.dart';
import 'auth_messages.dart';
import 'auth_service.dart';
import 'demo_accounts.dart';
import 'widgets/auth_scaffold.dart';

/// Écran de connexion par e-mail et mot de passe (§4.1, CORE-01).
///
/// Il porte aussi les deux boutons de démonstration exigés par le cahier des
/// charges : « Deux comptes de démonstration sont proposés en un tap sur
/// l'écran de connexion. » Ils sont posés en haut, avant le formulaire, parce
/// que c'est le chemin que prendront presque tous ceux qui découvrent
/// l'application.
class ConnexionScreen extends ConsumerStatefulWidget {
  /// Crée l'écran de connexion.
  const ConnexionScreen({this.retour, super.key});

  /// Route à rejoindre une fois connecté.
  ///
  /// Renseignée quand la connexion a été demandée au moment d'agir : on revient
  /// alors exactement là où le geste a été interrompu.
  final String? retour;

  @override
  ConsumerState<ConnexionScreen> createState() => _ConnexionScreenState();
}

class _ConnexionScreenState extends ConsumerState<ConnexionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _motDePasse = TextEditingController();

  bool _enCours = false;
  bool _motDePasseVisible = false;
  String? _erreur;

  @override
  void dispose() {
    _email.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  Future<void> _connecter(String email, String motDePasse) async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      await ref
          .read(authServiceProvider)
          .connexion(email: email, motDePasse: motDePasse);
      if (!mounted) return;

      // On DÉPILE plutôt que de naviguer : cet écran s'est ouvert par-dessus
      // celui où le geste a été interrompu, et le dépiler y ramène
      // exactement. C'est aussi ce qui termine le `await push` d'
      // exigerConnexion — un context.go() le laisserait en suspens.
      if (context.canPop()) {
        context.pop();
      } else {
        // Arrivée directe sur /connexion, par un lien profond : il n'y a rien
        // à dépiler.
        context.go(widget.retour ?? FerhaRoutes.profil);
      }
    } on Object catch (erreur) {
      if (!mounted) return;
      setState(() => _erreur = messageErreurAuth(erreur));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  void _soumettre() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _connecter(_email.text, _motDePasse.text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return AuthScaffold(
      titre: 'Connexion',
      sousTitre: 'Retrouvez vos demandes et vos réservations.',
      children: <Widget>[
        // Les deux comptes de démonstration (§4.1, CORE-01). Un seul tap.
        _BoutonDemo(
          compte: compteAmina,
          icone: Icons.person_outline,
          enCours: _enCours,
          onPressed: () =>
              _connecter(compteAmina.email, compteAmina.motDePasse),
        ),
        const SizedBox(height: 10),
        _BoutonDemo(
          compte: compteKarim,
          icone: Icons.storefront_outlined,
          enCours: _enCours,
          onPressed: () =>
              _connecter(compteKarim.email, compteKarim.motDePasse),
        ),

        const SizedBox(height: 24),
        Row(
          children: <Widget>[
            Expanded(child: Divider(color: colors.rule)),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
              child: Text(
                'ou avec votre compte',
                style: text.bodySmall?.copyWith(color: colors.inkTertiary),
              ),
            ),
            Expanded(child: Divider(color: colors.rule)),
          ],
        ),
        const SizedBox(height: 24),

        if (_erreur != null) AuthErreur(message: _erreur!),

        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
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
                autofillHints: const <String>[AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _soumettre(),
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
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
                validator: (valeur) => (valeur == null || valeur.isEmpty)
                    ? 'Entrez votre mot de passe.'
                    : null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _enCours ? null : _soumettre,
                  child: _enCours
                      ? const _Patiente()
                      : const Text('Se connecter'),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        TextButton(
          onPressed: _enCours
              ? null
              : () => context.push(FerhaRoutes.inscription),
          child: const Text('Pas encore de compte ? Créer un compte'),
        ),
      ],
    );
  }
}

/// Validation d'adresse partagée par la connexion et l'inscription.
///
/// Volontairement permissive : la seule autorité sur la validité d'une adresse
/// est le serveur qui lui écrira. On n'écarte ici que ce qui est
/// manifestement une faute de frappe.
String? validerEmail(String? valeur) {
  final email = valeur?.trim() ?? '';
  if (email.isEmpty) return 'Entrez votre adresse e-mail.';
  if (!email.contains('@') || !email.contains('.') || email.length < 5) {
    return 'Cette adresse ne ressemble pas à une adresse e-mail.';
  }
  return null;
}

/// Indicateur d'attente à l'intérieur d'un bouton.
class _Patiente extends StatelessWidget {
  const _Patiente();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      width: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}

/// Bouton « Entrer comme … », le chemin d'un tap du §4.1.
class _BoutonDemo extends StatelessWidget {
  const _BoutonDemo({
    required this.compte,
    required this.icone,
    required this.enCours,
    required this.onPressed,
  });

  final CompteDemo compte;
  final IconData icone;
  final bool enCours;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: enCours ? null : onPressed,
        icon: Icon(icone, size: 20),
        label: Text(compte.libelle),
        style: FilledButton.styleFrom(
          padding: const EdgeInsetsDirectional.symmetric(vertical: 16),
        ),
      ),
    );
  }
}
