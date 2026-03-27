# P1: Relais Client MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working Flutter client that connects to a Relais server, manages sessions, provides remote terminal access, and agent chat.

**Architecture:** Riverpod for state management, dio for REST, web_socket_channel for WebSocket, xterm dart package for terminal rendering. Services layer handles all server communication; providers expose reactive state to UI; screens compose widgets.

**Tech Stack:** Flutter 3.41, Dart, Riverpod, GoRouter, dio, web_socket_channel, xterm

**Spec:** `docs/specs/2026-03-27-relais-flutter-client-design.md`

**Working directory:** `/Users/zhouwei/Projects/ai/relais/client`

---

### Task 1: Data Models

**Files:**
- Create: `lib/models/server.dart`
- Create: `lib/models/session.dart`
- Create: `lib/models/agent_message.dart`

- [ ] **Step 1: Create Server model**

`lib/models/server.dart`:
```dart
class Server {
  final String id;
  final String name;
  final String url;
  final String token;

  const Server({
    required this.id,
    required this.name,
    required this.url,
    required this.token,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'token': token,
  };

  factory Server.fromJson(Map<String, dynamic> json) => Server(
    id: json['id'] as String,
    name: json['name'] as String,
    url: json['url'] as String,
    token: json['token'] as String,
  );
}
```

- [ ] **Step 2: Create Session model**

`lib/models/session.dart`:
```dart
enum SessionKind { terminal, agent }

enum SessionStatus {
  running, exited, ready, working, idle, crashed, initializing, waitingApproval, suspended;

  static SessionStatus fromString(String s) {
    return SessionStatus.values.firstWhere(
      (e) => e.name == s || e.name == s.replaceAll('_', ''),
      orElse: () => SessionStatus.running,
    );
  }
}

class Session {
  final String id;
  final String name;
  final SessionKind kind;
  final SessionStatus status;
  final String? parentId;
  final String createdAt;
  final int? exitCode;
  final String? shell;
  final int cols;
  final int rows;

  const Session({
    required this.id,
    required this.name,
    required this.kind,
    required this.status,
    this.parentId,
    required this.createdAt,
    this.exitCode,
    this.shell,
    this.cols = 80,
    this.rows = 24,
  });

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    id: json['id'] as String,
    name: json['name'] as String,
    kind: json['kind'] == 'agent' ? SessionKind.agent : SessionKind.terminal,
    status: SessionStatus.fromString(json['status'] as String? ?? 'running'),
    parentId: json['parent_id'] as String?,
    createdAt: json['created_at'] as String? ?? '',
    exitCode: json['exit_code'] as int?,
    shell: json['shell'] as String?,
    cols: json['cols'] as int? ?? 80,
    rows: json['rows'] as int? ?? 24,
  );

  bool get isAgent => kind == SessionKind.agent;
  bool get isTerminal => kind == SessionKind.terminal;
}
```

- [ ] **Step 3: Create AgentMessage model**

`lib/models/agent_message.dart`:
```dart
enum AgentMessageType {
  user, text, thinking, toolUse, toolResult, progress, turnComplete, error
}

class AgentMessage {
  final String id;
  final AgentMessageType type;
  final String content;
  final DateTime timestamp;
  final int? seq;
  // text
  final bool streaming;
  // tool_use
  final String? toolName;
  final String? toolId;
  final String? toolInput;
  // tool_result
  final String? toolOutput;
  final bool? isError;
  // error
  final String? severity;
  final String? guidance;
  // user_message
  final String? source;
  // turn_complete
  final double? costUsd;

  const AgentMessage({
    required this.id,
    required this.type,
    required this.content,
    required this.timestamp,
    this.seq,
    this.streaming = false,
    this.toolName,
    this.toolId,
    this.toolInput,
    this.toolOutput,
    this.isError,
    this.severity,
    this.guidance,
    this.source,
    this.costUsd,
  });

  factory AgentMessage.fromServerEvent(Map<String, dynamic> json) {
    final type = json['type'] as String;
    final seq = json['seq'] as int?;
    final now = DateTime.now();

    switch (type) {
      case 'user_message':
        return AgentMessage(
          id: 'user-${seq ?? now.millisecondsSinceEpoch}',
          type: AgentMessageType.user,
          content: json['text'] as String? ?? '',
          timestamp: now,
          seq: seq,
          source: json['source'] as String?,
        );
      case 'text':
        return AgentMessage(
          id: 'text-${seq ?? now.millisecondsSinceEpoch}',
          type: AgentMessageType.text,
          content: json['content'] as String? ?? '',
          timestamp: now,
          seq: seq,
          streaming: json['streaming'] as bool? ?? false,
        );
      case 'thinking':
        return AgentMessage(
          id: 'thinking-${seq ?? now.millisecondsSinceEpoch}',
          type: AgentMessageType.thinking,
          content: json['content'] as String? ?? '',
          timestamp: now,
          seq: seq,
        );
      case 'tool_use':
        return AgentMessage(
          id: 'tool_use-${seq ?? now.millisecondsSinceEpoch}',
          type: AgentMessageType.toolUse,
          content: 'Using ${json['name']}',
          timestamp: now,
          seq: seq,
          toolName: json['name'] as String?,
          toolId: json['id'] as String?,
          toolInput: json['input']?.toString(),
        );
      case 'tool_result':
        return AgentMessage(
          id: 'tool_result-${seq ?? now.millisecondsSinceEpoch}',
          type: AgentMessageType.toolResult,
          content: json['output'] as String? ?? '',
          timestamp: now,
          seq: seq,
          toolId: json['id'] as String?,
          toolOutput: json['output'] as String?,
          isError: json['is_error'] as bool?,
        );
      case 'progress':
        return AgentMessage(
          id: 'progress-${seq ?? now.millisecondsSinceEpoch}',
          type: AgentMessageType.progress,
          content: json['message'] as String? ?? '',
          timestamp: now,
          seq: seq,
        );
      case 'turn_complete':
        return AgentMessage(
          id: 'turn-${seq ?? now.millisecondsSinceEpoch}',
          type: AgentMessageType.turnComplete,
          content: 'Turn complete',
          timestamp: now,
          seq: seq,
          costUsd: (json['cost_usd'] as num?)?.toDouble(),
        );
      case 'error':
        return AgentMessage(
          id: 'error-${seq ?? now.millisecondsSinceEpoch}',
          type: AgentMessageType.error,
          content: json['message'] as String? ?? 'Unknown error',
          timestamp: now,
          seq: seq,
          severity: json['severity'] as String?,
          guidance: json['guidance'] as String?,
        );
      default:
        return AgentMessage(
          id: 'unknown-${now.millisecondsSinceEpoch}',
          type: AgentMessageType.text,
          content: '[Unknown message type: $type]',
          timestamp: now,
        );
    }
  }
}
```

- [ ] **Step 4: Verify and commit**

Run: `cd /Users/zhouwei/Projects/ai/relais/client && flutter analyze lib/models/`
Expected: No issues.

```bash
cd /Users/zhouwei/Projects/ai/relais && git add client/lib/models/
git commit -m "feat(client): add data models (Server, Session, AgentMessage)"
```

---

### Task 2: API Client Service

**Files:**
- Create: `lib/services/api_client.dart`

- [ ] **Step 1: Create API client**

`lib/services/api_client.dart` — REST client using dio. Handles all REST API calls:

```dart
import 'package:dio/dio.dart';
import '../models/session.dart';

class ApiClient {
  final Dio _dio;
  final String baseUrl;
  final String token;

  ApiClient({required this.baseUrl, required this.token})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          headers: {'Authorization': 'Bearer $token'},
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ));

  /// Check server health.
  Future<Map<String, dynamic>> getStatus() async {
    final resp = await _dio.get('/api/v1/status');
    return resp.data as Map<String, dynamic>;
  }

  /// List all sessions.
  Future<List<Session>> getSessions() async {
    final resp = await _dio.get('/api/v1/sessions');
    final list = resp.data as List;
    return list.map((e) => Session.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Create a new session.
  Future<Map<String, dynamic>> createSession({
    required String name,
    String type = 'terminal',
    String? provider,
    String? model,
    String? cwd,
  }) async {
    final resp = await _dio.post('/api/v1/sessions', data: {
      'name': name,
      'session_type': type,
      if (provider != null) 'provider': provider,
      if (model != null) 'model': model,
      if (cwd != null) 'cwd': cwd,
    });
    return resp.data as Map<String, dynamic>;
  }

  /// Delete a session.
  Future<void> deleteSession(String id) async {
    await _dio.delete('/api/v1/sessions/$id');
  }

  /// Get plugin list.
  Future<List<Map<String, dynamic>>> getPlugins() async {
    final resp = await _dio.get('/api/v1/plugins');
    final list = resp.data as List;
    return list.cast<Map<String, dynamic>>();
  }

  /// Get tunnel status.
  Future<Map<String, dynamic>> getTunnelStatus() async {
    final resp = await _dio.get('/api/v1/tunnel/status');
    return resp.data as Map<String, dynamic>;
  }

  void dispose() {
    _dio.close();
  }
}
```

- [ ] **Step 2: Verify and commit**

Run: `flutter analyze lib/services/`
Expected: No issues.

```bash
cd /Users/zhouwei/Projects/ai/relais && git add client/lib/services/api_client.dart
git commit -m "feat(client): add REST API client service"
```

---

### Task 3: WebSocket Services

**Files:**
- Create: `lib/services/terminal_connection.dart`
- Create: `lib/services/agent_connection.dart`

- [ ] **Step 1: Create terminal WebSocket connection**

`lib/services/terminal_connection.dart`:
```dart
import 'dart:async';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';

class TerminalConnection {
  WebSocketChannel? _channel;
  final String baseUrl;
  final String token;
  final String sessionId;

  final _outputController = StreamController<Uint8List>.broadcast();
  final _statusController = StreamController<String>.broadcast();

  Stream<Uint8List> get output => _outputController.stream;
  Stream<String> get status => _statusController.stream;

  TerminalConnection({
    required this.baseUrl,
    required this.token,
    required this.sessionId,
  });

  void connect() {
    final wsUrl = baseUrl.replaceFirst('http', 'ws');
    final uri = Uri.parse('$wsUrl/ws/terminal?session=$sessionId&token=$token');

    _channel = WebSocketChannel.connect(uri);
    _statusController.add('connected');

    _channel!.stream.listen(
      (data) {
        if (data is List<int>) {
          _outputController.add(Uint8List.fromList(data));
        } else if (data is String) {
          // JSON control messages (keepalive_ack, exit)
          // Could parse and handle, but terminal widget doesn't need them
        }
      },
      onError: (error) {
        _statusController.add('error');
      },
      onDone: () {
        _statusController.add('disconnected');
      },
    );
  }

  /// Send raw input bytes to terminal.
  void sendInput(String data) {
    _channel?.sink.add(data);
  }

  /// Send resize command.
  void resize(int cols, int rows) {
    _channel?.sink.add('{"type":"resize","cols":$cols,"rows":$rows}');
  }

  void dispose() {
    _channel?.sink.close();
    _outputController.close();
    _statusController.close();
  }
}
```

- [ ] **Step 2: Create agent WebSocket connection**

`lib/services/agent_connection.dart`:
```dart
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/agent_message.dart';

class AgentConnection {
  WebSocketChannel? _channel;
  final String baseUrl;
  final String token;
  final String sessionId;

  final _messageController = StreamController<AgentMessage>.broadcast();
  final _statusController = StreamController<String>.broadcast();

  Stream<AgentMessage> get messages => _messageController.stream;
  Stream<String> get status => _statusController.stream;

  AgentConnection({
    required this.baseUrl,
    required this.token,
    required this.sessionId,
  });

  void connect() {
    final wsUrl = baseUrl.replaceFirst('http', 'ws');
    final uri = Uri.parse('$wsUrl/ws/agent?session=$sessionId&token=$token');

    _channel = WebSocketChannel.connect(uri);

    _channel!.stream.listen(
      (data) {
        if (data is String) {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final type = json['type'] as String?;

          if (type == 'status') {
            _statusController.add(json['status'] as String? ?? 'unknown');
            return;
          }

          final msg = AgentMessage.fromServerEvent(json);
          _messageController.add(msg);
        }
      },
      onError: (error) {
        _statusController.add('error');
      },
      onDone: () {
        _statusController.add('disconnected');
      },
    );
  }

  /// Send a user message to the agent.
  void sendMessage(String text) {
    _channel?.sink.add(jsonEncode({'type': 'message', 'text': text}));
  }

  /// Cancel the current agent turn.
  void cancel() {
    _channel?.sink.add(jsonEncode({'type': 'cancel'}));
  }

  void dispose() {
    _channel?.sink.close();
    _messageController.close();
    _statusController.close();
  }
}
```

- [ ] **Step 3: Verify and commit**

Run: `flutter analyze lib/services/`
Expected: No issues.

```bash
cd /Users/zhouwei/Projects/ai/relais && git add client/lib/services/
git commit -m "feat(client): add terminal and agent WebSocket services"
```

---

### Task 4: Riverpod Providers

**Files:**
- Create: `lib/providers/server_provider.dart`
- Create: `lib/providers/session_provider.dart`
- Modify: `lib/app.dart` (wrap with ProviderScope)
- Modify: `lib/main.dart` (wrap with ProviderScope)

- [ ] **Step 1: Create server provider**

`lib/providers/server_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/server.dart';
import '../services/api_client.dart';

/// Current active server connection.
class ServerState {
  final Server? server;
  final ApiClient? apiClient;
  final bool connecting;
  final String? error;

  const ServerState({this.server, this.apiClient, this.connecting = false, this.error});

  ServerState copyWith({Server? server, ApiClient? apiClient, bool? connecting, String? error}) {
    return ServerState(
      server: server ?? this.server,
      apiClient: apiClient ?? this.apiClient,
      connecting: connecting ?? this.connecting,
      error: error,
    );
  }

  bool get isConnected => server != null && apiClient != null && error == null;
}

class ServerNotifier extends StateNotifier<ServerState> {
  ServerNotifier() : super(const ServerState());

  /// Connect to a server.
  Future<void> connect(String url, String token, {String name = 'Default'}) async {
    state = state.copyWith(connecting: true, error: null);

    final cleanUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final api = ApiClient(baseUrl: cleanUrl, token: token);

    try {
      await api.getStatus();
      final server = Server(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        url: cleanUrl,
        token: token,
      );
      state = ServerState(server: server, apiClient: api);

      // Save to local storage
      await _saveServer(server);
    } catch (e) {
      api.dispose();
      state = state.copyWith(connecting: false, error: e.toString());
    }
  }

  /// Disconnect from current server.
  void disconnect() {
    state.apiClient?.dispose();
    state = const ServerState();
  }

  /// Load saved servers from local storage.
  Future<List<Server>> loadSavedServers() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('saved_servers');
    if (data == null) return [];
    final list = jsonDecode(data) as List;
    return list.map((e) => Server.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _saveServer(Server server) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadSavedServers();
    existing.removeWhere((s) => s.url == server.url);
    existing.insert(0, server);
    await prefs.setString('saved_servers', jsonEncode(existing.map((s) => s.toJson()).toList()));
  }
}

final serverProvider = StateNotifierProvider<ServerNotifier, ServerState>((ref) {
  return ServerNotifier();
});
```

- [ ] **Step 2: Create session provider**

`lib/providers/session_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/session.dart';
import 'server_provider.dart';

class SessionNotifier extends StateNotifier<AsyncValue<List<Session>>> {
  final Ref ref;

  SessionNotifier(this.ref) : super(const AsyncValue.loading());

  /// Fetch all sessions from server.
  Future<void> refresh() async {
    final api = ref.read(serverProvider).apiClient;
    if (api == null) {
      state = const AsyncValue.data([]);
      return;
    }

    state = const AsyncValue.loading();
    try {
      final sessions = await api.getSessions();
      state = AsyncValue.data(sessions);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Create a new terminal session.
  Future<String?> createTerminal(String name) async {
    final api = ref.read(serverProvider).apiClient;
    if (api == null) return null;

    try {
      final result = await api.createSession(name: name, type: 'terminal');
      await refresh();
      return result['id'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Create a new agent session.
  Future<String?> createAgent(String name, {String provider = 'claude-code'}) async {
    final api = ref.read(serverProvider).apiClient;
    if (api == null) return null;

    try {
      final result = await api.createSession(name: name, type: 'agent', provider: provider);
      await refresh();
      return result['id'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Delete a session.
  Future<void> deleteSession(String id) async {
    final api = ref.read(serverProvider).apiClient;
    if (api == null) return;

    try {
      await api.deleteSession(id);
      await refresh();
    } catch (_) {}
  }
}

final sessionProvider = StateNotifierProvider<SessionNotifier, AsyncValue<List<Session>>>((ref) {
  return SessionNotifier(ref);
});
```

- [ ] **Step 3: Update main.dart to wrap with ProviderScope**

`lib/main.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: RelaisApp()));
}
```

- [ ] **Step 4: Verify and commit**

Run: `flutter analyze lib/providers/ lib/main.dart`
Expected: No issues.

```bash
cd /Users/zhouwei/Projects/ai/relais && git add client/lib/providers/ client/lib/main.dart
git commit -m "feat(client): add Riverpod providers (server connection, sessions)"
```

---

### Task 5: Connect Screen (with saved servers)

**Files:**
- Modify: `lib/screens/connect_screen.dart`
- Modify: `lib/app.dart` (add routes)

- [ ] **Step 1: Rewrite ConnectScreen with Riverpod**

Full rewrite of `lib/screens/connect_screen.dart` — uses `serverProvider` to connect, shows saved servers list, navigates to home on success.

Key behaviors:
- URL + token text fields (pre-filled from saved servers)
- "Connect" button calls `serverNotifier.connect()`
- Shows error snackbar on failure
- Shows saved servers as M3 ListTiles below the form
- On success, navigates to `/home`

- [ ] **Step 2: Update app.dart routes**

Add `/home` route pointing to `HomeScreen` (placeholder for now):
```dart
GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
```

- [ ] **Step 3: Verify and commit**

Run: `flutter build web`
Expected: Success.

```bash
cd /Users/zhouwei/Projects/ai/relais && git add client/lib/screens/ client/lib/app.dart
git commit -m "feat(client): connect screen with saved servers and Riverpod"
```

---

### Task 6: Home Screen (session list)

**Files:**
- Create: `lib/screens/home_screen.dart`
- Create: `lib/widgets/session_card.dart`

- [ ] **Step 1: Create SessionCard widget**

`lib/widgets/session_card.dart` — M3 Card showing session name, kind icon (terminal/agent), status chip, created time. Tap navigates to terminal or agent screen. Long-press shows delete option.

- [ ] **Step 2: Create HomeScreen**

`lib/screens/home_screen.dart`:
- AppBar with server name and disconnect button
- FAB with SpeedDial or BottomSheet to create terminal/agent
- `RefreshIndicator` wrapping `ListView` of `SessionCard`
- Uses `sessionProvider` (auto-refreshes on enter)
- Empty state: "No sessions yet" with create button

- [ ] **Step 3: Add routes for terminal and agent screens**

Update `lib/app.dart`:
```dart
GoRoute(path: '/terminal/:id', builder: (_, state) => TerminalScreen(sessionId: state.pathParameters['id']!)),
GoRoute(path: '/agent/:id', builder: (_, state) => AgentScreen(sessionId: state.pathParameters['id']!)),
```

- [ ] **Step 4: Verify and commit**

Run: `flutter build web`
Expected: Success.

```bash
cd /Users/zhouwei/Projects/ai/relais && git add client/lib/
git commit -m "feat(client): home screen with session list and navigation"
```

---

### Task 7: Terminal Screen

**Files:**
- Create: `lib/screens/terminal_screen.dart`
- Create: `lib/widgets/terminal_view.dart`
- Create: `lib/widgets/special_key_bar.dart`

- [ ] **Step 1: Create TerminalView widget**

`lib/widgets/terminal_view.dart` — wraps the `xterm` dart package `TerminalView` widget. Connects to `TerminalConnection`, pipes output to `Terminal` object, sends input back.

Key behaviors:
- Initialize `Terminal` from xterm package
- Connect `TerminalConnection` on init
- Pipe `connection.output` stream into `terminal.write()`
- Pipe `terminal.onOutput` into `connection.sendInput()`
- Send resize on layout change via `connection.resize()`

- [ ] **Step 2: Create SpecialKeyBar widget**

`lib/widgets/special_key_bar.dart` — row of M3 `FilterChip` buttons for Ctrl, Tab, Esc, arrows, etc. Only shown on mobile (check `Platform` or screen width). Sends escape sequences to terminal.

- [ ] **Step 3: Create TerminalScreen**

`lib/screens/terminal_screen.dart`:
- Full-screen layout with `TerminalView` filling available space
- `SpecialKeyBar` at bottom on mobile
- AppBar with session name, back button
- Handles connection lifecycle (connect on init, dispose on exit)

- [ ] **Step 4: Verify and commit**

Run: `flutter build web`
Expected: Success.

```bash
cd /Users/zhouwei/Projects/ai/relais && git add client/lib/
git commit -m "feat(client): terminal screen with xterm rendering and virtual keyboard"
```

---

### Task 8: Agent Chat Screen

**Files:**
- Create: `lib/screens/agent_screen.dart`
- Create: `lib/widgets/agent_chat.dart`
- Create: `lib/widgets/message_bubble.dart`

- [ ] **Step 1: Create MessageBubble widget**

`lib/widgets/message_bubble.dart` — renders a single `AgentMessage` with appropriate styling:
- `user`: right-aligned, primary color bubble
- `text`: left-aligned, surface variant, markdown rendered via `flutter_markdown`
- `thinking`: collapsed/expandable, muted color
- `toolUse`: M3 `Card.outlined` with tool name and expandable input
- `toolResult`: M3 `Card.outlined` with output, error styling if `isError`
- `progress`: center-aligned, small text
- `turnComplete`: center-aligned, success icon + cost
- `error`: M3 `Card.filled` with error color

- [ ] **Step 2: Create AgentChat widget**

`lib/widgets/agent_chat.dart` — `ListView.builder` of `MessageBubble` items. Auto-scrolls to bottom on new message. Takes `List<AgentMessage>` and scroll controller.

- [ ] **Step 3: Create AgentScreen**

`lib/screens/agent_screen.dart`:
- AppBar with session name
- `AgentChat` widget filling body
- Bottom text input bar with send button (M3 `TextField` + `IconButton`)
- Manages `AgentConnection` lifecycle
- Accumulates messages from `connection.messages` stream into local state
- Sends user message via `connection.sendMessage()` and adds to local state

- [ ] **Step 4: Verify and commit**

Run: `flutter build web`
Expected: Success.

```bash
cd /Users/zhouwei/Projects/ai/relais && git add client/lib/
git commit -m "feat(client): agent chat screen with message bubbles and markdown"
```

---

### Task 9: End-to-End Test

**Files:** None (testing only)

- [ ] **Step 1: Build web client**

Run: `cd /Users/zhouwei/Projects/ai/relais/client && flutter build web`
Expected: Success.

- [ ] **Step 2: Start Relais server**

Run: `cd /Users/zhouwei/Projects/ai/relais && make server-dev` (in background)
Expected: Server starts on localhost:3000.

- [ ] **Step 3: Run Flutter web and test manually**

Run: `cd /Users/zhouwei/Projects/ai/relais/client && flutter run -d chrome`

Test flow:
1. Enter `http://localhost:3000` and token → Connect
2. See empty session list → Create terminal session
3. Open terminal → See shell prompt, type commands
4. Go back → Create agent session
5. Open agent → Send message, see agent response

- [ ] **Step 4: Final commit**

```bash
cd /Users/zhouwei/Projects/ai/relais && git add .
git commit -m "chore: P1 MVP complete — connection, sessions, terminal, agent chat"
```
