import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/session.dart';
import '../providers/server_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/terminal_provider.dart';
import '../widgets/session_switcher.dart';
import '../widgets/terminal_view.dart';
import '../widgets/special_key_bar.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const TerminalScreen({super.key, required this.sessionId});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  }

  @override
  void dispose() {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(serverProvider).server;
    if (server == null) {
      return const Scaffold(body: Center(child: Text('Not connected')));
    }

    // Get or create persistent terminal session (no state modification)
    final session = ref.read(terminalManagerProvider).getOrCreate(
      sessionId: widget.sessionId,
      baseUrl: server.url,
      token: server.token,
    );

    final isMobile = MediaQuery.of(context).size.width < 600 && !kIsWeb;
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22),
        foregroundColor: const Color(0xFFc9d1d9),
        elevation: 0,
        toolbarHeight: 36,
        titleSpacing: 0,
        leading: BackButton(
          onPressed: () => context.go('/home'),
          style: const ButtonStyle(iconSize: WidgetStatePropertyAll(18)),
        ),
        title: Row(
          children: [
            SessionSwitcher(
              currentSessionId: widget.sessionId,
              filterKind: SessionKind.terminal,
            ),
            const SizedBox(width: 8),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: session.status == 'connected'
                    ? const Color(0xFF3fb950)
                    : const Color(0xFFd29922),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TerminalViewWidget(
              terminal: session.terminal,
              fontSize: settings.terminalFontSize,
            ),
          ),
          if (isMobile)
            SpecialKeyBar(
              onKey: (key) => session.connection.sendInput(key),
            ),
        ],
      ),
    );
  }
}
