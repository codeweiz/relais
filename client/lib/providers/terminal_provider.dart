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

    terminal.onOutput = (data) {
      connection.sendInput(data);
    };

    terminal.onResize = (cols, rows, pw, ph) {
      connection.resize(cols, rows);
    };

    final outputSub = connection.output.listen((Uint8List data) {
      try {
        terminal.write(utf8.decode(data, allowMalformed: true));
      } catch (_) {}
    });

    final session = TerminalSession._(
      terminal: terminal,
      connection: connection,
      outputSub: outputSub,
    );

    // Subscribe to status BEFORE connect so we don't miss the initial event
    connection.status.listen((s) {
      session.status = s;
    });

    connection.connect();

    return session;
  }

  void dispose() {
    _outputSub.cancel();
    connection.dispose();
  }
}

/// Simple session cache — NOT a StateNotifier, so it can be
/// accessed during build without triggering state modifications.
class TerminalManager {
  final _sessions = <String, TerminalSession>{};

  TerminalSession getOrCreate({
    required String sessionId,
    required String baseUrl,
    required String token,
  }) {
    return _sessions.putIfAbsent(
      sessionId,
      () => TerminalSession.connect(
        baseUrl: baseUrl,
        token: token,
        sessionId: sessionId,
      ),
    );
  }

  void remove(String sessionId) {
    _sessions[sessionId]?.dispose();
    _sessions.remove(sessionId);
  }

  void disposeAll() {
    for (final s in _sessions.values) {
      s.dispose();
    }
    _sessions.clear();
  }
}

/// Single instance, safe to read during build.
final terminalManagerProvider = Provider<TerminalManager>((ref) {
  final manager = TerminalManager();
  ref.onDispose(() => manager.disposeAll());
  return manager;
});
