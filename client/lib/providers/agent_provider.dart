import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/agent_message.dart';
import '../models/slash_command.dart';
import '../services/agent_connection.dart';

/// Ephemeral message types — removed on turn_complete.
const _ephemeralTypes = {
  AgentMessageType.toolUse,
  AgentMessageType.toolResult,
  AgentMessageType.progress,
  AgentMessageType.thinking,
};

/// Persistent agent session: connection + message history.
class AgentSession {
  final AgentConnection connection;
  final List<AgentMessage> messages = [];
  String status = 'connecting';
  bool waiting = false;

  List<SlashCommand>? _cachedCommands;
  StreamSubscription? _slashCmdSub;

  /// Cached slash commands from the agent, or null if not yet received.
  List<SlashCommand>? get availableCommands => _cachedCommands;

  StreamSubscription? _messageSub;
  StreamSubscription? _statusSub;

  /// Listeners that get notified when messages or state change.
  final _listeners = <void Function()>[];

  AgentSession._({required this.connection});

  factory AgentSession.connect({
    required String baseUrl,
    required String token,
    required String sessionId,
  }) {
    final connection = AgentConnection(
      baseUrl: baseUrl,
      token: token,
      sessionId: sessionId,
    );

    final session = AgentSession._(connection: connection);

    session._messageSub = connection.messages.listen((msg) {
      if (msg.type == AgentMessageType.turnComplete) {
        session.waiting = false;
        session.messages.removeWhere((m) => _ephemeralTypes.contains(m.type));
        session._notify();
        return;
      }

      if (msg.type == AgentMessageType.text) session.waiting = false;

      if (msg.type == AgentMessageType.text && msg.streaming) {
        final idx = session.messages.indexWhere((m) => m.id == msg.id);
        if (idx >= 0) {
          session.messages[idx] = msg;
        } else {
          session.messages.add(msg);
        }
      } else {
        session.messages.add(msg);
      }
      session._notify();
    });

    session._statusSub = connection.status.listen((s) {
      session.status = s;
      if (s == 'disconnected') {
        session._cachedCommands = null;
      }
      session._notify();
    });

    session._slashCmdSub = connection.slashCommands.listen((commands) {
      session._cachedCommands = commands;
      session._notify();
    });

    connection.connect();
    return session;
  }

  void sendMessage(String text) {
    waiting = true;
    connection.sendMessage(text);
    _notify();
  }

  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void _notify() {
    for (final l in _listeners) {
      l();
    }
  }

  void dispose() {
    _messageSub?.cancel();
    _statusSub?.cancel();
    _slashCmdSub?.cancel();
    connection.dispose();
  }
}

/// Manages persistent agent sessions, same pattern as TerminalManager.
class AgentSessionManager {
  final _sessions = <String, AgentSession>{};

  AgentSession getOrCreate({
    required String sessionId,
    required String baseUrl,
    required String token,
  }) {
    return _sessions.putIfAbsent(
      sessionId,
      () => AgentSession.connect(
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

final agentSessionManagerProvider = Provider<AgentSessionManager>((ref) {
  final manager = AgentSessionManager();
  ref.onDispose(() => manager.disposeAll());
  return manager;
});
