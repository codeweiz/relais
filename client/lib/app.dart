import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'theme/app_theme.dart';
import 'screens/connect_screen.dart';

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const ConnectScreen(),
    ),
  ],
);

class RelaisApp extends StatelessWidget {
  const RelaisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Relais',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}
