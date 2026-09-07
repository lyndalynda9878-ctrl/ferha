import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Barre d'onglets racine de l'application.
///
/// Chaque onglet garde sa propre pile de navigation : le [StatefulNavigationShell]
/// fourni par go_router conserve l'état de la branche non affichée.
class HomeShell extends StatelessWidget {
  /// Crée la coque d'onglets autour de [navigationShell].
  const HomeShell({required this.navigationShell, super.key});

  /// Coque de navigation gérée par `StatefulShellRoute.indexedStack`.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _goBranch,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Assistant',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: 'Favoris',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      // Un second tap sur l'onglet actif revient à sa racine.
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}
