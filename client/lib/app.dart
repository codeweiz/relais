import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'theme/app_theme.dart';
import 'providers/settings_provider.dart';
import 'screens/connect_screen.dart';
import 'screens/home_screen.dart';
import 'screens/terminal_screen.dart';
import 'screens/agent_screen.dart';
import 'screens/settings_screen.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const ConnectScreen(),
    ),
    GoRoute(
      path: '/home',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: const ValueKey('home'),
        child: const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    ),
    // Terminal and agent as sub-routes of /home so back works
    GoRoute(
      path: '/terminal/:id',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: ValueKey('terminal-${state.pathParameters['id']}'),
        child: TerminalScreen(sessionId: state.pathParameters['id']!),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    ),
    GoRoute(
      path: '/agent/:id',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: ValueKey('agent-${state.pathParameters['id']}'),
        child: AgentScreen(sessionId: state.pathParameters['id']!),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    // /office now redirects to /home since office is the home workspace
    GoRoute(
      path: '/office',
      redirect: (context, state) => '/home',
    ),
  ],
);

class RelaisApp extends ConsumerWidget {
  const RelaisApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp.router(
      title: 'Relais',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      locale: Locale(settings.locale),
      routerConfig: _router,
    );
  }
}
