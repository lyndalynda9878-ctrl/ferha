/// Configuration lue à la compilation, jamais écrite dans le dépôt.
///
/// Les valeurs arrivent par `--dart-define-from-file=env.json`. `env.json` est
/// dans `.gitignore` ; `env.example.json`, lui, est versionné et sert de
/// modèle.
///
/// ```bash
/// flutter run -d chrome --dart-define-from-file=env.json --print-dtd
/// ```
///
/// `String.fromEnvironment` est une constante de compilation : elle ne peut
/// être lue que dans un contexte `const`, et vaut la chaîne vide quand la clé
/// n'a pas été fournie. C'est cette chaîne vide, et elle seule, qui signale
/// une configuration absente.
library;

/// Les clés de configuration de l'application.
abstract final class FerhaEnv {
  /// URL du projet Supabase, de la forme `https://xxxx.supabase.co`.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Clé publique du projet Supabase.
  ///
  /// Publique au sens strict : elle part dans le bundle web et n'importe qui
  /// peut la lire. Ce n'est pas un secret, et ce n'est pas elle qui protège
  /// les données — ce sont les politiques RLS (§9). Elle reste malgré tout
  /// hors du dépôt : elle désigne un projet précis, et changer de projet ne
  /// doit pas demander de changer le code.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// Les clés attendues qui n'ont pas été fournies.
  ///
  /// Vide quand la configuration est complète.
  static List<String> get clesManquantes => <String>[
    if (supabaseUrl.isEmpty) 'SUPABASE_URL',
    if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
  ];

  /// Vrai quand toutes les clés attendues sont présentes.
  static bool get estComplete => clesManquantes.isEmpty;

  /// Message d'aide affiché quand il manque une clé.
  ///
  /// Il dit quoi faire, pas seulement ce qui ne va pas : un message d'erreur
  /// qui n'indique pas le geste suivant fait perdre le temps qu'il prétend
  /// faire gagner.
  static String get messageDAide {
    final manquantes = clesManquantes.join(', ');
    return '''
Configuration absente : $manquantes.

1. Copiez env.example.json en env.json, à la racine du dépôt.
2. Renseignez-y les deux valeurs, prises dans votre tableau de bord Supabase,
   Project Settings › API :
     SUPABASE_URL       l'URL du projet (https://xxxx.supabase.co)
     SUPABASE_ANON_KEY  la clé publique (anon / publishable)
3. Relancez avec :
     flutter run -d chrome --dart-define-from-file=env.json --print-dtd

env.json est ignoré par git : il ne partira jamais dans un commit.''';
  }
}
