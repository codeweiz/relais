import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';
import '../services/terminal_connection.dart';

/// Holds a persistent terminal session: xterm Terminal + WebSocket connection.
class TerminalSession {
  final Terminal terminal;
  final TerminalConnection connection;
  final StreamSubscription _outputSub;
  String status = 'connecting';

  TerminalSession._({
    required this.terminal,
    required this.connection,
    required StreamSubscription outputSub,
  }) : _outputSub = outputSub;

  /// Create and connect a new persistent terminal session.
  factory TerminalSession.connect({
    required String baseUrl,
    required String token,
    required String sessionId,
  }) {
    final terminal = Terminal(maxLines: 10000);
    final connection = TerminalConnection(
      baseUrl: baseUrl,
      token: token,
      sessionId: sessionId,
    );

    // Keyboard input → server
    terminal.onOutput = (data) {
      connection.sendInput(data);
    };

    // Resize → server
    terminal.onResize = (cols, rows, pw, ph) {
      connection.resize(cols, rows);
    };

    // Server output → terminal (with xterm dart bug workaround)
    final outputSub = connection.output.listen((Uint8List data) {
      try {
        terminal.write(utf8.decode(data, allowMalformed: true));
      } catch (_) {
        // xterm dart eraseLineToCursor bug (index -1)
      }
    });

    connection.connect();

    final session = TerminalSession._(
      terminal: terminal,
      connection: connection,
      outputSub: outputSub,
    );

    connection.status.listen((s) {
      session.status = s;
    });

    return session;
  }

  void dispose() {
    _outputSub.cancel();
    connection.dispose();
  }
}

/// Manages all persistent terminal sessions by session ID.
/// Terminals stay alive when navigating away and are reused on re-enter.
class TerminalManager extends StateNotifier<Map<String, TerminalSession>> {
  TerminalManager() : super({});

  /// Get or create a terminal session.
  TerminalSession getOrCreate({
    required String sessionId,
    required String baseUrl,
    required String token,
  }) {
    if (state.containsKey(sessionId)) {
      return state[sessionId]!;
    }

    final session = TerminalSession.connect(
      baseUrl: baseUrl,
      token: token,
      sessionId: sessionId,
    );

    state = {...state, sessionId: session};
    return session;
  }

  /// Remove and dispose a terminal session.
  void remove(String sessionId) {
    final session = state[sessionId];
    if (session != null) {
      session.dispose();
      state = Map.from(state)..remove(sessionId);
    }
  }

  @override
  void dispose() {
    for (final session in state.values) {
      session.dispose();
    }
    super.dispose();
  }
}

final terminalManagerProvider =
    StateNotifierProvider<TerminalManager, Map<String, TerminalSession>>((ref) {
  return TerminalManager();
});
