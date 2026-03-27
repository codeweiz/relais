import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    final server = ref.read(serverProvider).server;
    if (server != null) {
      _connection = TerminalConnection(
        baseUrl: server.url,
        token: server.token,
        sessionId: widget.sessionId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_connection == null) {
      return const Scaffold(body: Center(child: Text('Not connected')));
    }

    // Show special key bar on mobile-sized screens
    final showKeyBar = MediaQuery.of(context).size.width < 600 && !kIsWeb;

    return Scaffold(
      appBar: AppBar(
        title: Text('Terminal ${widget.sessionId.substring(0, 6)}...'),
      ),
      body: Column(
        children: [
          Expanded(
            child: TerminalViewWidget(connection: _connection!),
          ),
          if (showKeyBar)
            SpecialKeyBar(
              onKey: (key) => _connection!.sendInput(key),
            ),
        ],
      ),
    );
  }
}
