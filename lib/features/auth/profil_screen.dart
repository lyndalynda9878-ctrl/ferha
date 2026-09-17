import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/l10n/locale_controller.dart';
import '../../core/router/routes.dart';
import '../../core/theme/ferha_colors.dart';
import '../../core/theme/ferha_radii.dart';
import '../../core/widgets/bouton_theme.dart';
import 'auth_messages.dart';
import 'auth_providers.dart';
import 'auth_service.dart';

/// Onglet « Profil ».
///
/// Deux visages, et c'est le point : **cet écran ne redirige jamais vers la
/// connexion**. Un visiteur non connecté a le droit d'être là, comme il a le
/// droit de chercher une salle et d'en consulter la fiche. On lui montre ce
/// qu'un compte apporterait, et on lui laisse le choix.
///
/// La connexion ne se demande qu'au moment d'agir — envoyer une demande,
/// déposer un avis — et c'est `exigerConnexion` (routes.dart) qui s'en charge,
/// depuis l'écran qui porte le geste.
class ProfilScreen extends ConsumerWidget {
  /// Crée l'onglet profil.
  const ProfilScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connecte = ref.watch(estConnecteProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).profilTitre),
        actions: <Widget>[
          // LES DEUX PRÉFÉRENCES D'AFFICHAGE SE TIENNENT AU MÊME ENDROIT : la
          // langue et le thème répondent à la même question — comment voulez-
          // vous lire ? — et on ne devrait pas avoir à chercher l'une après
          // avoir trouvé l'autre.
          const BoutonTheme(),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            // LA BASCULE DE LANGUE (§10, CORE-03).
            //
            // Elle annonce la langue vers laquelle elle mène, jamais celle
            // qu'on lit : un bouton « Français » sur une page française ne dit
            // pas s'il change quelque chose. C'est `switchLanguage`, et c'est
            // pour cela que la clé porte l'AUTRE langue dans chaque fichier.
            //
            // Elle écrit deux fois — l'appareil et `profiles.locale` — et
            // l'écran a déjà changé quand la seconde écriture part. Voir
            // LocaleController.
            child: TextButton.icon(
              onPressed: () async {
                await ref.read(localeProvider.notifier).toggle();
                // Le profil porte `locale` : on le relit pour que la ligne
                // « Langue » plus bas ne reste pas sur l'ancienne valeur.
                ref.invalidate(profilProvider);
              },
              icon: const Icon(Icons.translate, size: 18),
              label: Text(AppLocalizations.of(context).switchLanguage),
            ),
          ),
        ],
      ),
      body: connecte ? const _ProfilConnecte() : const _ProfilVisiteur(),
    );
  }
}

// -----------------------------------------------------------------------------
// Visiteur — non connecté
// -----------------------------------------------------------------------------

class _ProfilVisiteur extends StatelessWidget {
  const _ProfilVisiteur();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final textes = AppLocalizations.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Icon(Icons.person_outline, size: 48, color: colors.inkTertiary),
              const SizedBox(height: 16),
              Text(
                textes.profilNonConnecteTitre,
                textAlign: TextAlign.center,
                style: text.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                textes.profilNonConnecteTexte,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.push(FerhaRoutes.connexion),
                  child: Text(textes.authSeConnecter),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => context.push(FerhaRoutes.inscription),
                  child: Text(textes.authCreerUnCompte),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Connecté
// -----------------------------------------------------------------------------

class _ProfilConnecte extends ConsumerWidget {
  const _ProfilConnecte();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profil = ref.watch(profilProvider);
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final textes = AppLocalizations.of(context);

    return profil.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (erreur, _) => _ErreurProfil(
        message: messageErreurAuth(textes, erreur),
        onReessayer: () => ref.invalidate(profilProvider),
      ),
      data: (donnees) {
        // Ne devrait pas arriver : le déclencheur handle_new_user (migration
        // 007) crée le profil dans la transaction du compte. Si ce cas se
        // présente, c'est que la migration n'est pas appliquée — et le dire
        // vaut mieux qu'afficher un écran vide.
        if (donnees == null) {
          return _ErreurProfil(
            message: textes.profilSansProfil,
            onReessayer: () => ref.invalidate(profilProvider),
          );
        }

        final nom = (donnees['full_name'] as String?) ?? '';
        final email = (donnees['email'] as String?) ?? '';
        final telephone = donnees['phone'] as String?;
        final estProprietaire = (donnees['is_owner'] as bool?) ?? false;
        final estAdmin = (donnees['is_admin'] as bool?) ?? false;

        return ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 32),
          children: <Widget>[
            Center(
              child: CircleAvatar(
                radius: 36,
                backgroundColor: colors.primarySoft,
                child: Text(
                  _initiales(nom),
                  style: text.headlineSmall?.copyWith(
                    color: colors.primaryDeep,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(child: Text(nom, style: text.headlineSmall)),
            const SizedBox(height: 4),
            Center(
              child: Text(
                email,
                style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Wrap(
                spacing: 8,
                children: <Widget>[
                  _Etiquette(
                    libelle: estProprietaire
                        ? textes.profilRoleProprietaire
                        : textes.profilRoleClient,
                    icone: estProprietaire
                        ? Icons.storefront_outlined
                        : Icons.search,
                  ),
                  if (estAdmin)
                    _Etiquette(
                      libelle: textes.profilRoleAdministration,
                      icone: Icons.shield_outlined,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Le suivi des demandes, avant les informations du compte : c'est
            // ce qu'on vient chercher ici une fois la première demande partie.
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => context.push(FerhaRoutes.mesReservations),
                icon: const Icon(Icons.event_note_outlined, size: 18),
                label: Text(textes.mesReservations),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsetsDirectional.symmetric(vertical: 14),
                ),
              ),
            ),

            // INSCRIRE UNE SALLE, POUR TOUT COMPTE CONNECTÉ (§4.3, OWN-01).
            //
            // Sans condition de rôle, et c'est le point : « un même compte peut
            // être client et propriétaire » (§2), et beaucoup de propriétaires
            // réservent aussi des salles pour leur famille. Un bouton réservé à
            // `is_owner` n'apparaîtrait jamais à personne — c'est justement ce
            // geste-ci qui lève le drapeau, dans `creer_salle()` (017).
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push(FerhaRoutes.publierSalle),
                icon: const Icon(Icons.add_business_outlined, size: 18),
                label: Text(textes.profilPublierMaSalle),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsetsDirectional.symmetric(vertical: 14),
                ),
              ),
            ),

            // L'espace propriétaire, pour qui en est un.
            //
            // Le bouton n'apparaît qu'avec `is_owner`, et ce n'est PAS ce qui
            // protège le tableau de bord : les fonctions de 014 refusent d'une
            // part un appel sans session, d'autre part une salle qui n'est pas
            // la vôtre. Le cacher évite seulement de proposer à une cliente une
            // porte qui ne s'ouvrirait sur rien.
            if (estProprietaire) ...<Widget>[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () =>
                      context.push(FerhaRoutes.proprietaireTableau),
                  icon: const Icon(Icons.storefront_outlined, size: 18),
                  label: Text(textes.profilMesSalles),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsetsDirectional.symmetric(
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            _Ligne(
              icone: Icons.phone_outlined,
              libelle: textes.profilTelephone,
              // LE NUMÉRO RESTE EN CHIFFRES LATINS, comme partout (§10) : il
              // s'affiche tel que la base le porte, sans mise en forme — c'est
              // celui qu'on compose.
              valeur: telephone ?? textes.profilNonRenseigne,
              estVide: telephone == null,
            ),
            // CE QUI S'AFFICHE EST LA LANGUE ACTIVE, et non `profiles.locale`.
            //
            // Les deux disent la même chose une fois l'écriture passée ; mais
            // entre le tap et la réponse de Supabase — ou quand le réseau est
            // tombé et que l'écriture a échoué en silence — c'est la langue
            // qu'on LIT qui est vraie. Montrer le profil ferait dire à l'écran
            // « Français » pendant qu'il est écrit en arabe.
            _Ligne(
              icone: Icons.translate,
              libelle: textes.profilLangue,
              valeur: ref.watch(localeProvider).languageCode == 'ar'
                  ? textes.langueArabe
                  : textes.langueFrancais,
            ),

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _deconnecter(context, ref),
                icon: const Icon(Icons.logout, size: 18),
                label: Text(textes.profilSeDeconnecter),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deconnecter(BuildContext context, WidgetRef ref) async {
    final textes = AppLocalizations.of(context);
    try {
      await ref.read(authServiceProvider).deconnexion();
    } on Object catch (erreur) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageErreurAuth(textes, erreur))),
      );
    }
  }
}

/// Les initiales d'un nom, pour l'avatar.
String _initiales(String nom) {
  final mots = nom.trim().split(RegExp(r'\s+')).where((m) => m.isNotEmpty);
  if (mots.isEmpty) return '?';
  if (mots.length == 1) return mots.first.characters.first.toUpperCase();
  return (mots.first.characters.first + mots.last.characters.first)
      .toUpperCase();
}

class _Etiquette extends StatelessWidget {
  const _Etiquette({required this.libelle, required this.icone});

  final String libelle;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    return Chip(
      avatar: Icon(icone, size: 16, color: colors.primaryDeep),
      label: Text(libelle),
      side: BorderSide(color: colors.rule),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({
    required this.icone,
    required this.libelle,
    required this.valeur,
    this.estVide = false,
  });

  final IconData icone;
  final String libelle;
  final String valeur;
  final bool estVide;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Container(
        padding: const EdgeInsetsDirectional.all(16),
        decoration: BoxDecoration(
          color: colors.surfaceSecondary,
          borderRadius: FerhaRadii.cardBorder,
          border: Border.all(color: colors.ruleSoft),
        ),
        child: Row(
          children: <Widget>[
            Icon(icone, size: 20, color: colors.inkTertiary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                libelle,
                style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
              ),
            ),
            Text(
              valeur,
              style: text.bodyMedium?.copyWith(
                color: estVide ? colors.inkTertiary : colors.ink,
                fontStyle: estVide ? FontStyle.italic : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErreurProfil extends StatelessWidget {
  const _ErreurProfil({required this.message, required this.onReessayer});

  final String message;
  final VoidCallback onReessayer;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: onReessayer,
                child: Text(AppLocalizations.of(context).reessayer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
