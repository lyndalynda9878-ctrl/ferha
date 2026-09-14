import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/router/routes.dart';
import '../../core/theme/ferha_colors.dart';
import '../../core/theme/ferha_radii.dart';
import '../../core/validation/telephone.dart';
import '../auth/auth_providers.dart';
import '../search/widgets/etats.dart';
import 'owner_messages.dart';
import 'owner_providers.dart';
import 'salle_du_proprietaire.dart';

/// Le récapitulatif d'un brouillon, et le geste qui l'envoie (§4.4, ADM-01).
///
/// POURQUOI UN ÉCRAN DE PLUS, ALORS QUE LE FORMULAIRE POURRAIT TOUT ENVOYER.
/// Deux raisons, et la seconde compte davantage.
///
/// La première est technique et arrive au J13 : les photos (OWN-02) ont besoin
/// d'un `venue_id` pour leur chemin de Storage `{venue_id}/{uuid}.webp`. Il faut
/// donc que la salle existe avant qu'on puisse lui en attacher une, et
/// l'écran des photos viendra se glisser entre le formulaire et celui-ci.
///
/// La seconde est humaine. Envoyer sa salle à la validation est le moment où
/// l'on cesse de remplir et où l'on s'engage — l'équipe Ferha va lire ce qu'on a
/// écrit. Un dernier écran qui redit ce qui part, avant le bouton qui l'envoie,
/// est ce qui fait qu'on relit. Et tant qu'on ne l'a pas appuyé, la salle reste
/// un brouillon que personne ne voit : rien n'est perdu si l'on referme.
///
/// C'EST AUSSI ICI QU'ON DEMANDE LE NUMÉRO, et pas au formulaire. ADM-01 veut
/// un « propriétaire joignable » : le numéro appartient donc à l'instant où la
/// salle part à la validation, pas à sa description. Il est prérempli depuis le
/// profil — un propriétaire qui inscrit sa deuxième salle ne le retape pas — et
/// c'est `envoyer_salle_en_validation()` (020) qui l'écrit dans
/// `profiles.phone`, en même temps qu'elle change le statut. Les deux vont
/// ensemble ou pas du tout.
///
/// LA SALLE EST RELUE DEPUIS LA BASE, PAS REÇUE DU FORMULAIRE. On pourrait la
/// passer par `extra` — ce serait plus rapide d'une requête. Mais ce qu'il faut
/// montrer ici est ce qui A ÉTÉ ENREGISTRÉ, pas ce qu'on croit avoir envoyé :
/// c'est tout l'intérêt d'un récapitulatif. Et sur le web, un rechargement de
/// page perdrait un `extra` là où il ne perd pas un identifiant d'adresse.
class RecapitulatifSalleScreen extends ConsumerStatefulWidget {
  /// Crée le récapitulatif.
  const RecapitulatifSalleScreen({required this.venueId, super.key});

  /// La salle qui vient d'être inscrite.
  final String venueId;

  @override
  ConsumerState<RecapitulatifSalleScreen> createState() =>
      _RecapitulatifSalleScreenState();
}

class _RecapitulatifSalleScreenState
    extends ConsumerState<RecapitulatifSalleScreen> {
  bool _envoiEnCours = false;
  String? _erreur;

  /// Le numéro auquel joindre le propriétaire.
  final _telephone = TextEditingController();

  /// Vrai dès que le champ a reçu le numéro du profil — ou que le propriétaire
  /// y a touché.
  ///
  /// SANS CE DRAPEAU, LE PRÉREMPLISSAGE ÉCRASERAIT LA SAISIE. Le profil arrive
  /// de façon asynchrone et se relit à chaque changement de session ; recopier
  /// sa valeur à chaque `build` reposerait l'ancien numéro sous les doigts de
  /// quelqu'un en train d'en taper un nouveau.
  bool _telephonePose = false;

  @override
  void dispose() {
    _telephone.dispose();
    super.dispose();
  }

  /// Pose le numéro du profil dans le champ, une seule fois.
  void _preremplit(Map<String, dynamic>? profil) {
    if (_telephonePose) return;
    final numero = profil?['phone'] as String?;
    if (numero == null) return;

    _telephone.text = numero;
    _telephonePose = true;
  }

  Future<void> _envoyer() async {
    setState(() {
      _envoiEnCours = true;
      _erreur = null;
    });

    try {
      await ref
          .read(publicationDeSalleServiceProvider)
          .envoyer(widget.venueId, _telephone.text);
      if (!mounted) return;

      // go et non push : on ne revient pas sur un récapitulatif dont le bouton
      // ne ferait plus rien. Le tableau de bord prend la suite, et il montre
      // désormais la salle avec son bandeau « En attente de validation ».
      context.go(FerhaRoutes.proprietaireTableau);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Votre salle est envoyée. L’équipe Ferha la vérifie avant '
            'publication.',
          ),
        ),
      );
    } on Object catch (erreur) {
      if (!mounted) return;
      setState(() => _erreur = messageErreurPublication(erreur));
    } finally {
      if (mounted) setState(() => _envoiEnCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final espace = ref.watch(espaceProprietaireProvider);
    _preremplit(ref.watch(profilProvider).value);

    // La salle se retrouve dans la liste du propriétaire, qui vient d'être
    // rechargée par le service — `owner_venues()` rend aussi les brouillons.
    final salle = espace.value?.salles
        .where((s) => s.id == widget.venueId)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Votre salle est prête')),
      body: switch (espace) {
        AsyncError(:final error) => EtatErreur(
          titre: 'Votre salle n’a pas pu être relue',
          erreur: error,
          onReessayer: () =>
              ref.read(espaceProprietaireProvider.notifier).reessayer(),
        ),
        AsyncData() when salle == null => EtatVide(
          icone: Icons.help_outline,
          titre: 'Cette salle est introuvable',
          explication:
              'Elle n’apparaît pas dans vos salles. Elle a peut-être été '
              'supprimée depuis un autre appareil.',
          pistes: <Widget>[
            FilledButton.icon(
              onPressed: () => context.go(FerhaRoutes.proprietaireTableau),
              icon: const Icon(Icons.storefront_outlined, size: 18),
              label: const Text('Mes salles'),
            ),
          ],
        ),
        AsyncData() => _Contenu(
          salle: salle!,
          telephone: _telephone,
          manqueTelephone: TelephoneAlgerien.ceQuiManque(
            AppLocalizations.of(context),
            _telephone.text,
          ),
          onTelephoneChange: () => setState(() {
            _telephonePose = true;
            // Le refus précédent ne survit pas à une correction : on vient de
            // changer ce qu'il reprochait.
            _erreur = null;
          }),
          enCours: _envoiEnCours,
          erreur: _erreur,
          onEnvoyer: _envoyer,
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Contenu extends StatelessWidget {
  const _Contenu({
    required this.salle,
    required this.telephone,
    required this.manqueTelephone,
    required this.onTelephoneChange,
    required this.enCours,
    required this.erreur,
    required this.onEnvoyer,
  });

  final SalleDuProprietaire salle;
  final TextEditingController telephone;

  /// Ce qui manque au numéro, ou `null` s'il va bien.
  final String? manqueTelephone;

  final VoidCallback onTelephoneChange;
  final bool enCours;
  final String? erreur;
  final VoidCallback onEnvoyer;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    // Une salle déjà envoyée n'a plus de geste à offrir. On arrive ici par un
    // lien direct, ou en revenant en arrière après l'envoi.
    final dejaEnvoyee = !salle.statut.estBrouillon;

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 32),
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsetsDirectional.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceSecondary,
            borderRadius: FerhaRadii.cardBorder,
            border: Border.all(color: colors.ruleSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                salle.nom,
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                salle.localisation,
                style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.visibility_off_outlined,
                    size: 16,
                    color: colors.inkTertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      salle.statut.libelle,
                      style: text.bodySmall?.copyWith(
                        color: colors.inkTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        Text(
          dejaEnvoyee
              ? 'Votre salle attend la validation de l’équipe Ferha. Vous '
                    'serez prévenu dès qu’elle sera publiée.'
              // ADM-01 en une phrase, et sans détour : « aucune salle n'est
              // visible avant contrôle humain ». Le dire ici évite qu'un
              // propriétaire cherche sa salle dans la recherche le soir même
              // et croie que rien n'a marché.
              : 'Votre salle est enregistrée, mais personne ne la voit encore. '
                    'En l’envoyant, vous la soumettez à l’équipe Ferha, qui '
                    'vérifie les photos et l’adresse avant de la publier.',
          style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
        ),

        // CE QUI MANQUE ENCORE, ET QU'ON NE CACHE PAS. Une salle sans grille
        // tarifaire (OWN-03) ne sortira dans aucune recherche : `search_venues()`
        // fait une jointure interne sur `venue_pricing`. L'écran des tarifs
        // n'existe pas encore ; taire cela laisserait un propriétaire attendre
        // des demandes qui ne viendraient jamais.
        const SizedBox(height: 16),
        Container(
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
                  'Il vous restera à saisir vos tarifs par créneau. Sans eux, '
                  'votre salle ne peut pas être proposée aux clients.',
                  style: text.bodySmall?.copyWith(color: colors.roseInk),
                ),
              ),
            ],
          ),
        ),

        // LE NUMÉRO, JUSTE AU-DESSUS DU BOUTON QUI L'ENVOIE. Une salle déjà
        // partie n'a plus rien à demander : le champ disparaît avec le bouton.
        if (!dejaEnvoyee) ...<Widget>[
          const SizedBox(height: 24),
          Text(
            'TÉLÉPHONE POUR VOUS JOINDRE',
            style: text.labelSmall?.copyWith(
              color: colors.inkTertiary,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: telephone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: '0770 11 22 33'),
            onChanged: (_) => onTelephoneChange(),
          ),
          const SizedBox(height: 6),
          Text(
            // À QUOI IL SERT, ET À QUI IL N'EST PAS DONNÉ. Un numéro demandé
            // sans explication se donne à contrecœur ou se donne faux. Les
            // deux phrases répondent aux deux questions qu'on se pose : qui
            // m'appelle, et qui d'autre le verra (§9).
            'L’équipe Ferha vous appelle pour vérifier votre salle. Vos '
            'clients ne le voient qu’après avoir accepté une réservation.',
            style: text.bodySmall?.copyWith(color: colors.inkTertiary),
          ),
        ],

        if (erreur != null) ...<Widget>[
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsetsDirectional.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: FerhaRadii.cardBorder,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.error_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    erreur!,
                    style: text.bodySmall?.copyWith(color: colors.ink),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),
        if (!dejaEnvoyee) ...<Widget>[
          // CE QUI MANQUE, DIT À CÔTÉ DU BOUTON ÉTEINT — même règle qu'au
          // formulaire : un bouton gris sans phrase fait relire l'écran.
          if (manqueTelephone != null) ...<Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.info_outline, size: 16, color: colors.inkSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    manqueTelephone!,
                    style: text.bodySmall?.copyWith(color: colors.inkSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (enCours || manqueTelephone != null)
                  ? null
                  : onEnvoyer,
              style: FilledButton.styleFrom(
                padding: const EdgeInsetsDirectional.symmetric(vertical: 16),
              ),
              child: enCours
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Envoyer pour validation'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: enCours
                ? null
                : () => context.go(FerhaRoutes.proprietaireTableau),
            child: Text(dejaEnvoyee ? 'Mes salles' : 'Plus tard'),
          ),
        ),
      ],
    );
  }
}
