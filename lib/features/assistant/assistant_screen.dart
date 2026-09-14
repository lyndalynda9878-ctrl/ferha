import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/direction_du_texte.dart';
import '../../core/router/routes.dart';
import '../../core/theme/ferha_colors.dart';
import '../../core/theme/ferha_radii.dart';
import 'assistant_messages.dart';
import 'assistant_providers.dart';
import 'message_assistant.dart';
import 'widgets/carte_salle_citee.dart';

/// Le champ où l'on écrit sa question.
const Key cleChampQuestion = Key('assistant-question');

/// Le bouton qui envoie.
const Key cleEnvoyerQuestion = Key('assistant-envoyer');

/// Le bouton qui efface la conversation.
const Key cleEffacerConversation = Key('assistant-effacer');

/// Ce qui s'affiche pendant que l'assistant cherche.
const Key cleAssistantCherche = Key('assistant-cherche');

/// L'assistant de recherche — l'écran 8 des maquettes, onglet central.
///
/// IL S'UTILISE SANS COMPTE, et c'est la première chose à savoir. Chercher une
/// salle ne demande pas de s'inscrire : ce sont les étapes 1 et 2 du parcours du
/// §3, et cet écran en est une. Aucune redirection ne le protège, et rien ici ne
/// lit la session. La connexion se demande plus loin, au moment d'ENGAGER
/// quelque chose — sur le bouton de demande de la fiche qu'une carte ouvre.
///
/// CHAQUE QUESTION EST TRAITÉE SEULE. `ai-chat` reçoit une question et rien
/// d'autre : l'agent ne relit pas ce qui précède. Ce que cet écran montre est le
/// compte rendu de ce qui s'est dit, pas un fil que l'assistant aurait en
/// mémoire — « et avec un jardin ? » posé tout seul ne marchera pas, et l'écran
/// d'accueil le dit à sa façon en proposant des questions ENTIÈRES.
///
/// CE QU'IL N'AFFICHE PAS, ET QUI EST DANS LA MAQUETTE : la rangée de puces
/// « Avec espace femmes · Moins de 200 000 · Avec jardin ». Elles n'existent que
/// si la fonction en renvoie, et elle n'en renvoie pas — elle rédige une
/// réponse, elle ne propose pas de suite. Trois boutons posés à la main qui
/// relanceraient une recherche que personne n'a choisie seraient de la
/// décoration qui ment. Le champ est lu (`suggestions`) : le jour où la fonction
/// le remplira, la rangée apparaîtra sans qu'on touche à cet écran.
class AssistantScreen extends ConsumerStatefulWidget {
  /// Crée l'écran de l'assistant.
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final TextEditingController _question = TextEditingController();
  final ScrollController _defilement = ScrollController();

  /// Vrai quand l'attente dure assez pour qu'on doive l'expliquer.
  bool _attenteLongue = false;
  Timer? _minuterie;

  @override
  void dispose() {
    _minuterie?.cancel();
    _question.dispose();
    _defilement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(conversationProvider);

    // Une réponse qui arrive doit se voir. Le défilement est demandé APRÈS la
    // trame courante : la liste n'a pas encore la hauteur du nouveau message au
    // moment où l'on construit.
    ref.listen(conversationProvider, (_, _) => _versLeBas());

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.auto_awesome, size: 18),
            SizedBox(width: 8),
            Text('Assistant Ferha'),
          ],
        ),
        actions: <Widget>[
          // Le « ⟲ » de la maquette. Éteint sur une conversation vide — il n'y
          // a rien à effacer — et pendant l'attente : effacer sous une réponse
          // en route la ferait arriver dans le vide.
          IconButton(
            key: cleEffacerConversation,
            tooltip: 'Effacer la conversation',
            onPressed: etat.estVide || etat.enAttente
                ? null
                : () => ref.read(conversationProvider.notifier).effacer(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: etat.estVide
                ? _Accueil(onQuestion: _envoyer)
                : _Fil(
                    etat: etat,
                    defilement: _defilement,
                    attenteLongue: _attenteLongue,
                    onQuestion: _envoyer,
                  ),
          ),
          _BarreDeSaisie(
            controleur: _question,
            // UN SEUL BOOLÉEN BLOQUE TOUT : le champ, le bouton, et la touche
            // « envoyer » du clavier. Trois conditions séparées finiraient par
            // se désaccorder, et l'une d'elles laisserait passer une seconde
            // question — c'est-à-dire un second appel au modèle.
            bloque: etat.enAttente,
            onEnvoyer: () => _envoyer(_question.text),
          ),
        ],
      ),
    );
  }

  void _envoyer(String question) {
    final propre = question.trim();
    if (propre.isEmpty || ref.read(conversationProvider).enAttente) return;

    _question.clear();
    FocusScope.of(context).unfocus();

    // L'EXPLICATION DE LA LENTEUR S'ARME AVANT L'APPEL, et se désarme avec lui.
    // Le service d'empreintes dort quand personne ne l'a réveillé de la
    // journée ; la première question peut alors demander une minute. Dire
    // pourquoi au bout de huit secondes vaut mieux que laisser quelqu'un
    // regarder une roue tourner en se demandant si c'est cassé.
    _minuterie?.cancel();
    setState(() => _attenteLongue = false);
    _minuterie = Timer(delaiAvantExplication, () {
      if (mounted) setState(() => _attenteLongue = true);
    });

    unawaited(
      ref.read(conversationProvider.notifier).demander(propre).whenComplete(() {
        _minuterie?.cancel();
        if (mounted) setState(() => _attenteLongue = false);
      }),
    );
  }

  void _versLeBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_defilement.hasClients) return;
      _defilement.animateTo(
        _defilement.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }
}

// -----------------------------------------------------------------------------
// Le fil
// -----------------------------------------------------------------------------

class _Fil extends StatelessWidget {
  const _Fil({
    required this.etat,
    required this.defilement,
    required this.attenteLongue,
    required this.onQuestion,
  });

  final EtatConversation etat;
  final ScrollController defilement;
  final bool attenteLongue;
  final ValueChanged<String> onQuestion;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: defilement,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
      children: <Widget>[
        for (final message in etat.messages) ...<Widget>[
          _Message(message: message, onQuestion: onQuestion),
          const SizedBox(height: 12),
        ],
        if (etat.enAttente) _EnRecherche(attenteLongue: attenteLongue),
      ],
    );
  }
}

/// Un message — le mien, celui de l'assistant, ou une panne.
class _Message extends StatelessWidget {
  const _Message({required this.message, required this.onQuestion});

  final MessageAssistant message;
  final ValueChanged<String> onQuestion;

  @override
  Widget build(BuildContext context) {
    final deMoi = message.auteur == AuteurDuMessage.moi;

    return Column(
      crossAxisAlignment: deMoi
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: <Widget>[
        _Bulle(message: message),

        // LES CARTES SONT SOUS LA BULLE ET NON DEDANS. La maquette les met en
        // rangée pleine largeur, débordant du texte : une salle est un objet à
        // part, pas un morceau de phrase. Elles défilent horizontalement, parce
        // qu'à cinq salles une colonne remplirait l'écran et cacherait la
        // question suivante.
        if (message.salles.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          _RangeeDeSalles(salles: message.salles),
        ],

        // Les relances, si et seulement si la fonction en a renvoyé. Voir
        // l'en-tête de l'écran : rien de décoratif.
        if (message.suggestions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          _Suggestions(
            suggestions: message.suggestions,
            onQuestion: onQuestion,
          ),
        ],
      ],
    );
  }
}

/// La bulle de texte.
///
/// LA BULLE APPARTIENT À L'ÉCRAN, LE TEXTE À SA LANGUE. La bulle se place au
/// début ou à la fin de la ligne selon la langue de l'APPLICATION — c'est ce qui
/// fait qu'en arabe mes messages passent à gauche et ceux de l'assistant à
/// droite, comme dans toutes les messageries arabes. Le paragraphe, lui, se lit
/// dans le sens de SA langue : une réponse en arabe à une question en darja
/// s'écrit de droite à gauche même dans une application en français, sans quoi
/// la ponctuation se retrouve du mauvais côté et la phrase devient illisible.
class _Bulle extends StatelessWidget {
  const _Bulle({required this.message});

  final MessageAssistant message;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final deMoi = message.auteur == AuteurDuMessage.moi;
    final echec = message.estUnEchec;

    final fond = deMoi
        ? colors.primary
        : (echec ? colors.slotBookedSoft : colors.surfaceSecondary);
    final encre = deMoi
        ? colors.onPrimary
        : (echec ? colors.slotBooked : colors.inkSecondary);

    return Align(
      alignment: deMoi
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.84,
        ),
        child: Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 13,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: fond,
            borderRadius: FerhaRadii.cardBorder,
            border: echec ? Border.all(color: colors.slotBooked) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (echec) ...<Widget>[
                Icon(Icons.cloud_off_outlined, size: 17, color: encre),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: TexteDansSaLangue(
                  message.texte,
                  style: text.bodyMedium?.copyWith(color: encre, height: 1.45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RangeeDeSalles extends StatelessWidget {
  const _RangeeDeSalles({required this.salles});

  final List<SalleCitee> salles;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 172,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: salles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final salle = salles[i];
          return CarteSalleCitee(
            key: cleCarteSalleCitee(salle.venueId),
            salle: salle,
            // LA VRAIE FICHE, ET AUCUN PARAMÈTRE DE PLUS. La fiche tarife pour
            // aujourd'hui quand on n'apporte ni date ni créneau — c'est écrit
            // dans `FerhaRoutes.salle`. Recopier ici la date que l'agent a
            // COMPRISE serait la traiter comme un choix de l'utilisateur, et
            // l'agent la devine parfois : « le 14 août » sans année devient un
            // 14 août que personne n'a confirmé. La fiche pose la question
            // elle-même, dans son calendrier.
            onTap: () => context.push(FerhaRoutes.salleDe(salle.venueId)),
          );
        },
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.suggestions, required this.onQuestion});

  final List<String> suggestions;
  final ValueChanged<String> onQuestion;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final suggestion in suggestions)
          ActionChip(
            label: Text(suggestion),
            backgroundColor: colors.roseSoft,
            labelStyle: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: colors.roseInk),
            side: BorderSide.none,
            shape: const RoundedRectangleBorder(
              borderRadius: FerhaRadii.chipBorder,
            ),
            onPressed: () => onQuestion(suggestion),
          ),
      ],
    );
  }
}

/// « L'assistant cherche… », et la raison de la lenteur quand elle dure.
class _EnRecherche extends StatelessWidget {
  const _EnRecherche({required this.attenteLongue});

  final bool attenteLongue;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Align(
      key: cleAssistantCherche,
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 13,
          vertical: 10,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.84,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceSecondary,
          borderRadius: FerhaRadii.cardBorder,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    assistantCherche,
                    style: text.bodyMedium?.copyWith(
                      color: colors.inkSecondary,
                    ),
                  ),
                  if (attenteLongue) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      assistantChercheLongtemps,
                      style: text.bodySmall?.copyWith(
                        color: colors.inkTertiary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// L'accueil de l'écran, et la barre de saisie
// -----------------------------------------------------------------------------

/// Ce qu'on voit avant d'avoir rien demandé.
///
/// TROIS QUESTIONS ENTIÈRES, ET NON TROIS MOTS-CLÉS. Elles montrent ce que
/// l'agent sait faire — une wilaya, une capacité, une date, un budget dans la
/// même phrase — et elles montrent surtout qu'on peut lui parler comme on parle.
/// Celle du milieu est en darja, parce que c'est ainsi qu'on cherche une salle
/// en Algérie, et que rien d'autre dans l'application ne le dit.
///
/// CE NE SONT PAS DES SUGGESTIONS DE L'AGENT. Elles ne prétendent pas savoir ce
/// qui existe : ce sont des exemples de FORMULATION, écrits ici, et l'agent
/// répondra « je n'ai rien trouvé » si rien ne correspond. C'est la différence
/// avec les puces de la maquette, qui prétendraient filtrer un résultat.
class _Accueil extends StatelessWidget {
  const _Accueil({required this.onQuestion});

  final ValueChanged<String> onQuestion;

  static const List<String> _exemples = <String>[
    'Une salle à Oran pour 300 personnes le 14 août, moins de 250 000 DA',
    'kayen salle f Blida fiha espace femmes ?',
    'Comment je bloque une date ?',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 40, 24, 16),
      children: <Widget>[
        Icon(Icons.auto_awesome, size: 40, color: colors.primary),
        const SizedBox(height: 16),
        Text(
          'Décrivez la fête que vous préparez',
          textAlign: TextAlign.center,
          style: text.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'La wilaya, le nombre d’invités, la date, votre budget — en français, '
          'en arabe ou en darja. L’assistant ne propose que des salles qui '
          'existent, aux prix de la base.',
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(
            color: colors.inkSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        for (final exemple in _exemples)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 8),
            child: _Exemple(texte: exemple, onTap: () => onQuestion(exemple)),
          ),
      ],
    );
  }
}

class _Exemple extends StatelessWidget {
  const _Exemple({required this.texte, required this.onTap});

  final String texte;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: FerhaRadii.cardBorder,
        side: BorderSide(color: colors.ruleSoft),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: FerhaRadii.cardBorder,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                // L'exemple en darja est en écriture latine, mais le jour où
                // l'un d'eux sera en arabe, il se lira dans son sens.
                child: TexteDansSaLangue(
                  texte,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.inkSecondary),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.north_east, size: 15, color: colors.inkTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// La barre du bas — le champ et le bouton rond de la maquette.
class _BarreDeSaisie extends StatefulWidget {
  const _BarreDeSaisie({
    required this.controleur,
    required this.bloque,
    required this.onEnvoyer,
  });

  final TextEditingController controleur;
  final bool bloque;
  final VoidCallback onEnvoyer;

  @override
  State<_BarreDeSaisie> createState() => _BarreDeSaisieState();
}

class _BarreDeSaisieState extends State<_BarreDeSaisie> {
  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    // ÉTEINT SUR UN CHAMP VIDE AUTANT QUE PENDANT L'ATTENTE. Les deux
    // conditions se lisent ici, en un seul endroit, et le bouton ne peut pas
    // dire autre chose que ce que fera l'appui.
    final peutEnvoyer =
        !widget.bloque && widget.controleur.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: colors.background,
        border: BorderDirectional(top: BorderSide(color: colors.ruleSoft)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                key: cleChampQuestion,
                controller: widget.controleur,
                // LE CHAMP SE FERME PENDANT L'ATTENTE, il ne se contente pas de
                // refuser l'envoi. Écrire une seconde question pendant que la
                // première cherche donne l'impression qu'elle partira, et elle
                // ne partira pas.
                enabled: !widget.bloque,
                minLines: 1,
                maxLines: 4,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (peutEnvoyer) widget.onEnvoyer();
                },
                decoration: InputDecoration(
                  hintText: widget.bloque
                      ? assistantCherche
                      : 'Posez votre question…',
                  // Le compteur de caractères de Material encombre une barre de
                  // conversation pour rien : la limite existe pour borner ce qui
                  // part au modèle, pas pour être lue.
                  counterText: '',
                  filled: true,
                  fillColor: colors.surfaceSecondary,
                  border: OutlineInputBorder(
                    borderRadius: FerhaRadii.chipBorder,
                    borderSide: BorderSide(color: colors.rule),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: FerhaRadii.chipBorder,
                    borderSide: BorderSide(color: colors.rule),
                  ),
                  contentPadding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 2),
              child: IconButton.filled(
                key: cleEnvoyerQuestion,
                onPressed: peutEnvoyer ? widget.onEnvoyer : null,
                // LA FLÈCHE RESTE UNE FLÈCHE PENDANT L'ATTENTE, elle ne devient
                // pas une roue. C'est la bulle du fil qui dit que ça cherche —
                // à l'endroit où la réponse va apparaître. Deux indicateurs pour
                // une seule attente feraient chercher lequel dit vrai.
                icon: const Icon(Icons.arrow_upward, size: 20),
                tooltip: 'Envoyer',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
