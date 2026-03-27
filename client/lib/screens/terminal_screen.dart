import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/server_provider.dart';
import '../services/terminal_connection.dart';
import '../widgets/terminal_view.dart';
import '../widgets/special_key_bar.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const TerminalScreen({super.key, required this.sessionId});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  TerminalConnection? _connection;
  String _status = 'connecting';

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    final server = ref.read(serverProvider).server;
    if (server != null) {
      _connection = TerminalConnection(
        baseUrl: server.url,
        token: server.token,
        sessionId: widget.sessionId,
      );
      _connection!.status.listen((s) {
        if (mounted) setState(() => _status = s);
      });
    }
  }

  @override
  void dispose() {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_connection == null) {
      return const Scaffold(body: Center(child: Text('Not connected')));
    }

    final isMobile = MediaQuery.of(context).size.width < 600 && !kIsWeb;

    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161b22),
        foregroundColor: const Color(0xFFc9d1d9),
        elevation: 0,
        toolbarHeight: 36,
        titleSpacing: 0,
        leading: BackButton(
          onPressed: () => Navigator.pop(context),
          style: const ButtonStyle(iconSize: WidgetStatePropertyAll(18)),
        ),
        title: Row(
          children: [
            const Icon(Icons.terminal, size: 14, color: Color(0xFF8b949e)),
            const SizedBox(width: 6),
            Text(
              widget.sessionId,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'JetBrains Mono, monospace',
                color: Color(0xFF8b949e),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _status == 'connected'
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
            child: TerminalViewWidget(connection: _connection!),
          ),
          if (isMobile)
            SpecialKeyBar(
              onKey: (key) => _connection!.sendInput(key),
            ),
        ],
      ),
    );
  }
}
