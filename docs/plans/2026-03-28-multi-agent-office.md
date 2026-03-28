# Multi-Agent Office Visualization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a gamified 2D "Office" visualization panel showing all running agents as avatars with real-time status and activity bubbles, plus the server-side status aggregation infrastructure.

**Architecture:** Server adds an `AgentStatusRegistry` that derives agent activity from existing `AgentEvent` stream, exposes via REST API + WebSocket broadcast. Client adds a new Office screen with Flutter `CustomPainter` rendering agent avatars, status rings, and activity bubbles.

**Tech Stack:** Rust/Axum (server), Flutter/Dart with CustomPainter (client), Riverpod (state), GoRouter (navigation)

**Spec:** `docs/specs/2026-03-28-multi-agent-office-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `server/crates/core/src/agent/status_registry.rs` | Create | AgentStatusRegistry with DashMap, status derivation |
| `server/crates/core/src/agent/mod.rs` | Modify | Export status_registry module |
| `server/crates/core/src/agent/manager.rs` | Modify | Integrate registry: create/remove entries, update on events |
| `server/crates/core/src/events.rs` | Modify | Add `AgentActivityChanged` control event variant |
| `server/crates/core/src/lib.rs` | Modify | Add status_registry to CoreState |
| `server/crates/server/src/api/agents.rs` | Create | GET /api/v1/agents/status handler |
| `server/crates/server/src/api/mod.rs` | Modify | Export agents module |
| `server/crates/server/src/router.rs` | Modify | Add agents/status route |
| `server/crates/server/src/ws/status.rs` | Modify | Serialize AgentActivityChanged events |
| `client/lib/models/agent_status.dart` | Create | AgentStatusInfo model |
| `client/lib/services/api_client.dart` | Modify | Add getAgentStatuses() method |
| `client/lib/providers/agent_status_provider.dart` | Create | Global agent status provider |
| `client/lib/widgets/office_painter.dart` | Create | 2D floor + agent rendering CustomPainter |
| `client/lib/screens/office_screen.dart` | Create | Office page scaffold with animations |
| `client/lib/screens/home_screen.dart` | Modify | Add Office icon button to AppBar |
| `client/lib/app.dart` | Modify | Add /office route |
| `client/lib/l10n/strings.dart` | Modify | Add Office-related i18n strings |

---

### Task 1: Server — AgentStatusRegistry

**Files:**
- Create: `server/crates/core/src/agent/status_registry.rs`
- Modify: `server/crates/core/src/agent/mod.rs`

- [ ] **Step 1: Create status_registry.rs**

Create `server/crates/core/src/agent/status_registry.rs`:

```rust
//! Agent Status Registry — aggregated real-time status for all agents.

use std::time::Instant;

use dashmap::DashMap;
use serde::Serialize;

/// Activity state of an agent.
#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum AgentActivity {
    Idle,
    Working,
    Thinking,
    ToolCalling,
    Error,
}

impl std::fmt::Display for AgentActivity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AgentActivity::Idle => write!(f, "idle"),
            AgentActivity::Working => write!(f, "working"),
            AgentActivity::Thinking => write!(f, "thinking"),
            AgentActivity::ToolCalling => write!(f, "tool_calling"),
            AgentActivity::Error => write!(f, "error"),
        }
    }
}

/// Aggregated status for a single agent.
#[derive(Debug, Clone)]
pub struct AgentStatusEntry {
    pub session_id: String,
    pub name: String,
    pub provider: String,
    pub status: AgentActivity,
    pub activity: String,
    pub cost_usd: Option<f64>,
    pub updated_at: Instant,
}

/// JSON-serializable snapshot of agent status (for REST API).
#[derive(Debug, Serialize)]
pub struct AgentStatusSnapshot {
    pub session_id: String,
    pub name: String,
    pub provider: String,
    pub status: AgentActivity,
    pub activity: String,
    pub cost_usd: Option<f64>,
}

impl From<&AgentStatusEntry> for AgentStatusSnapshot {
    fn from(entry: &AgentStatusEntry) -> Self {
        Self {
            session_id: entry.session_id.clone(),
            name: entry.name.clone(),
            provider: entry.provider.clone(),
            status: entry.status.clone(),
            activity: entry.activity.clone(),
            cost_usd: entry.cost_usd,
        }
    }
}

/// Thread-safe registry of all agent statuses.
pub struct AgentStatusRegistry {
    entries: DashMap<String, AgentStatusEntry>,
}

impl AgentStatusRegistry {
    pub fn new() -> Self {
        Self {
            entries: DashMap::new(),
        }
    }

    /// Register a new agent.
    pub fn register(&self, session_id: &str, name: &str, provider: &str) {
        self.entries.insert(
            session_id.to_string(),
            AgentStatusEntry {
                session_id: session_id.to_string(),
                name: name.to_string(),
                provider: provider.to_string(),
                status: AgentActivity::Idle,
                activity: String::new(),
                cost_usd: None,
                updated_at: Instant::now(),
            },
        );
    }

    /// Remove an agent.
    pub fn unregister(&self, session_id: &str) {
        self.entries.remove(session_id);
    }

    /// Update activity. Returns true if the status actually changed (for throttling).
    pub fn update(
        &self,
        session_id: &str,
        status: AgentActivity,
        activity: &str,
        cost_usd: Option<f64>,
    ) -> bool {
        if let Some(mut entry) = self.entries.get_mut(session_id) {
            let changed = entry.status != status || entry.activity != activity;
            entry.status = status;
            entry.activity = activity.to_string();
            if let Some(cost) = cost_usd {
                entry.cost_usd = Some(entry.cost_usd.unwrap_or(0.0) + cost);
            }
            entry.updated_at = Instant::now();
            changed
        } else {
            false
        }
    }

    /// Get a snapshot of all agents for the REST API.
    pub fn snapshot(&self) -> Vec<AgentStatusSnapshot> {
        self.entries
            .iter()
            .map(|e| AgentStatusSnapshot::from(e.value()))
            .collect()
    }
}
```

- [ ] **Step 2: Export module in mod.rs**

In `server/crates/core/src/agent/mod.rs`, add:

```rust
pub mod status_registry;
```

- [ ] **Step 3: Verify compilation**

Run: `cd /Users/zhouwei/Projects/ai/relais/server && cargo check -p relais-core 2>&1 | tail -3`

- [ ] **Step 4: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add server/crates/core/src/agent/status_registry.rs server/crates/core/src/agent/mod.rs
git commit -m "feat(server): add AgentStatusRegistry for aggregated agent status"
```

---

### Task 2: Server — Integrate registry into AgentManager + events

**Files:**
- Modify: `server/crates/core/src/lib.rs`
- Modify: `server/crates/core/src/events.rs`
- Modify: `server/crates/core/src/agent/manager.rs`

- [ ] **Step 1: Add AgentActivityChanged to ControlEvent**

In `server/crates/core/src/events.rs`, add a new variant to `ControlEvent` after `PluginError`:

```rust
    AgentActivityChanged {
        session_id: SessionId,
        status: String,
        activity: String,
    },
```

- [ ] **Step 2: Add status_registry to CoreState**

In `server/crates/core/src/lib.rs`, add `status_registry` field to `CoreState`:

```rust
    pub status_registry: Arc<agent::status_registry::AgentStatusRegistry>,
```

Find where `CoreState` is constructed (likely in `new()` or a builder) and add:

```rust
status_registry: Arc::new(agent::status_registry::AgentStatusRegistry::new()),
```

- [ ] **Step 3: Integrate registry in AgentManager**

In `server/crates/core/src/agent/manager.rs`:

Add import:
```rust
use super::status_registry::{AgentActivity, AgentStatusRegistry};
```

Add `status_registry` field to `AgentManager`:
```rust
pub struct AgentManager {
    agents: DashMap<SessionId, ManagedAgent>,
    event_bus: Arc<EventBus>,
    status_registry: Arc<AgentStatusRegistry>,
}
```

Update `AgentManager::new()` to accept and store the registry:
```rust
pub fn new(event_bus: Arc<EventBus>, status_registry: Arc<AgentStatusRegistry>) -> Self {
    Self {
        agents: DashMap::new(),
        event_bus,
        status_registry,
    }
}
```

In `create_agent()`, after inserting the agent into `self.agents`, register with the registry:
```rust
self.status_registry.register(&session_id, &name, &kind.to_string());
```

In `kill_agent()`, before removing from `self.agents`, unregister:
```rust
self.status_registry.unregister(session_id);
```

- [ ] **Step 4: Update event router to update registry**

In `start_event_router()`, add status registry updates. The method needs access to the registry. Pass it as a parameter:

```rust
fn start_event_router(
    &self,
    session_id: String,
    backend: &AcpBackend,
    event_history: Arc<Mutex<Vec<AgentEvent>>>,
) {
```

Add `let status_registry = self.status_registry.clone();` and `let event_bus_for_status = self.event_bus.clone();` at the start alongside the existing clones.

Inside the `Ok(event) =>` arm, after the existing EventBus publish, add:

```rust
                        // Update status registry and broadcast activity change
                        let (activity_status, activity_text, event_cost) = match &event {
                            AgentEvent::Text(content) => {
                                let summary: String = content.chars().take(50).collect();
                                (AgentActivity::Working, summary, None)
                            }
                            AgentEvent::Thinking(_) => {
                                (AgentActivity::Thinking, "Thinking...".to_string(), None)
                            }
                            AgentEvent::ToolUse { name, .. } => {
                                (AgentActivity::ToolCalling, format!("Using: {}", name), None)
                            }
                            AgentEvent::ToolResult { .. } => {
                                (AgentActivity::Working, "Processing result...".to_string(), None)
                            }
                            AgentEvent::TurnComplete { cost_usd, .. } => {
                                (AgentActivity::Idle, String::new(), *cost_usd)
                            }
                            AgentEvent::Error(msg) => {
                                let summary: String = msg.chars().take(80).collect();
                                (AgentActivity::Error, summary, None)
                            }
                            AgentEvent::UserMessage { .. } => {
                                (AgentActivity::Working, "Processing message...".to_string(), None)
                            }
                            AgentEvent::AvailableCommands(_) | AgentEvent::Progress(_) => {
                                (AgentActivity::Working, String::new(), None)
                            }
                        };

                        if !activity_text.is_empty() || matches!(activity_status, AgentActivity::Idle) {
                            let changed = status_registry.update(
                                &sid,
                                activity_status.clone(),
                                &activity_text,
                                event_cost,
                            );
                            if changed {
                                event_bus_for_status.publish_control(
                                    ControlEvent::AgentActivityChanged {
                                        session_id: sid.clone(),
                                        status: activity_status.to_string(),
                                        activity: activity_text,
                                    },
                                );
                            }
                        }
```

- [ ] **Step 5: Fix CoreState construction**

Find where `AgentManager::new()` is called (in `lib.rs` or wherever `CoreState` is built) and pass the status_registry. Read the file to find the exact location and update the constructor call.

- [ ] **Step 6: Verify compilation**

Run: `cd /Users/zhouwei/Projects/ai/relais/server && cargo check 2>&1 | tail -5`

- [ ] **Step 7: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add server/crates/core/src/lib.rs server/crates/core/src/events.rs server/crates/core/src/agent/manager.rs
git commit -m "feat(server): integrate AgentStatusRegistry into event pipeline"
```

---

### Task 3: Server — REST API + WebSocket broadcast

**Files:**
- Create: `server/crates/server/src/api/agents.rs`
- Modify: `server/crates/server/src/api/mod.rs`
- Modify: `server/crates/server/src/router.rs`
- Modify: `server/crates/server/src/ws/status.rs`

- [ ] **Step 1: Create agents.rs API handler**

Create `server/crates/server/src/api/agents.rs`:

```rust
use axum::{extract::State, Json};

use crate::state::AppState;
use relais_core::agent::status_registry::AgentStatusSnapshot;

/// GET /api/v1/agents/status — returns all agents' current status.
pub async fn get_agent_statuses(
    State(state): State<AppState>,
) -> Json<Vec<AgentStatusSnapshot>> {
    Json(state.core.status_registry.snapshot())
}
```

- [ ] **Step 2: Export in api/mod.rs**

In `server/crates/server/src/api/mod.rs`, add:

```rust
pub mod agents;
```

- [ ] **Step 3: Add route in router.rs**

In `server/crates/server/src/router.rs`, add import:

```rust
use crate::api::agents;
```

Add route in `api_routes()` function after the tunnel routes:

```rust
        // Agents
        .route("/agents/status", get(agents::get_agent_statuses))
```

- [ ] **Step 4: Add AgentActivityChanged to WebSocket serialization**

In `server/crates/server/src/ws/status.rs`, add a new arm to `control_event_to_json()` before the closing `};`:

```rust
        ControlEvent::AgentActivityChanged {
            session_id,
            status,
            activity,
        } => {
            serde_json::json!({
                "type": "agent_activity",
                "session_id": session_id,
                "status": status,
                "activity": activity,
            })
        }
```

- [ ] **Step 5: Build the full server**

Run: `cd /Users/zhouwei/Projects/ai/relais/server && cargo build 2>&1 | tail -5`

- [ ] **Step 6: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add server/crates/server/src/api/agents.rs server/crates/server/src/api/mod.rs server/crates/server/src/router.rs server/crates/server/src/ws/status.rs
git commit -m "feat(server): add GET /api/v1/agents/status + WebSocket activity broadcast"
```

---

### Task 4: Client — AgentStatusInfo model + API method

**Files:**
- Create: `client/lib/models/agent_status.dart`
- Modify: `client/lib/services/api_client.dart`

- [ ] **Step 1: Create agent_status.dart**

Create `client/lib/models/agent_status.dart`:

```dart
class AgentStatusInfo {
  final String sessionId;
  final String name;
  final String provider;
  final String status;
  final String activity;
  final double? costUsd;

  const AgentStatusInfo({
    required this.sessionId,
    required this.name,
    required this.provider,
    required this.status,
    required this.activity,
    this.costUsd,
  });

  factory AgentStatusInfo.fromJson(Map<String, dynamic> json) =>
      AgentStatusInfo(
        sessionId: json['session_id'] as String,
        name: json['name'] as String,
        provider: json['provider'] as String,
        status: json['status'] as String,
        activity: json['activity'] as String? ?? '',
        costUsd: (json['cost_usd'] as num?)?.toDouble(),
      );
}
```

- [ ] **Step 2: Add API method to ApiClient**

In `client/lib/services/api_client.dart`, add import:

```dart
import '../models/agent_status.dart';
```

Add method:

```dart
  Future<List<AgentStatusInfo>> getAgentStatuses() async {
    final resp = await _dio.get('/api/v1/agents/status');
    final list = resp.data as List;
    return list
        .map((e) => AgentStatusInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }
```

- [ ] **Step 3: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add client/lib/models/agent_status.dart client/lib/services/api_client.dart
git commit -m "feat(client): add AgentStatusInfo model and API method"
```

---

### Task 5: Client — AgentStatusProvider

**Files:**
- Create: `client/lib/providers/agent_status_provider.dart`

- [ ] **Step 1: Create the provider**

Create `client/lib/providers/agent_status_provider.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/agent_status.dart';
import '../providers/server_provider.dart';
import '../services/api_client.dart';

/// Manages aggregated status for all agents. Fetches initial snapshot via REST,
/// then subscribes to /ws/status for real-time activity updates.
class AgentStatusNotifier extends StateNotifier<Map<String, AgentStatusInfo>> {
  final ApiClient _api;
  final String _baseUrl;
  final String _token;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _refreshTimer;

  AgentStatusNotifier({
    required ApiClient api,
    required String baseUrl,
    required String token,
  })  : _api = api,
        _baseUrl = baseUrl,
        _token = token,
        super({}) {
    _init();
  }

  Future<void> _init() async {
    await refresh();
    _connectWebSocket();
    // Periodic refresh as fallback (every 5 seconds)
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => refresh(),
    );
  }

  Future<void> refresh() async {
    try {
      final statuses = await _api.getAgentStatuses();
      final map = <String, AgentStatusInfo>{};
      for (final s in statuses) {
        map[s.sessionId] = s;
      }
      state = map;
    } catch (_) {
      // Silently ignore refresh errors
    }
  }

  void _connectWebSocket() {
    final wsUrl = _baseUrl.replaceFirst('http', 'ws');
    final uri = Uri.parse('$wsUrl/ws/status?token=$_token');
    _channel = WebSocketChannel.connect(uri);

    _sub = _channel!.stream.listen(
      (data) {
        if (data is String) {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final type = json['type'] as String?;

          if (type == 'agent_activity') {
            final sessionId = json['session_id'] as String;
            final existing = state[sessionId];
            if (existing != null) {
              final updated = AgentStatusInfo(
                sessionId: sessionId,
                name: existing.name,
                provider: existing.provider,
                status: json['status'] as String? ?? existing.status,
                activity: json['activity'] as String? ?? '',
                costUsd: existing.costUsd,
              );
              state = {...state, sessionId: updated};
            }
          } else if (type == 'session_deleted') {
            final sessionId = json['session_id'] as String;
            state = Map.from(state)..remove(sessionId);
          } else if (type == 'session_created') {
            // New session — refresh to get full info
            refresh();
          }
        }
      },
      onError: (_) {},
      onDone: () {
        // Reconnect after a short delay
        Future.delayed(const Duration(seconds: 3), _connectWebSocket);
      },
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}

/// Provider for agent status. Requires server connection to be active.
final agentStatusProvider =
    StateNotifierProvider<AgentStatusNotifier, Map<String, AgentStatusInfo>>(
        (ref) {
  final server = ref.watch(serverProvider).server;
  if (server == null) {
    return AgentStatusNotifier(
      api: ApiClient(baseUrl: '', token: ''),
      baseUrl: '',
      token: '',
    );
  }
  return AgentStatusNotifier(
    api: ApiClient(baseUrl: server.url, token: server.token),
    baseUrl: server.url,
    token: server.token,
  );
});
```

- [ ] **Step 2: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add client/lib/providers/agent_status_provider.dart
git commit -m "feat(client): add AgentStatusProvider with REST + WebSocket updates"
```

---

### Task 6: Client — i18n strings

**Files:**
- Modify: `client/lib/l10n/strings.dart`

- [ ] **Step 1: Add strings**

In `client/lib/l10n/strings.dart`, add before the `_t` helper:

```dart
  static String get office => _t('办公室', 'Office');
  static String get noAgentsRunning => _t('暂无运行中的 Agent', 'No agents running');
  static String get tapToChat => _t('点击进入对话', 'Tap to chat');
  static String get statusIdle => _t('空闲', 'Idle');
  static String get statusWorking => _t('工作中', 'Working');
  static String get statusThinking => _t('思考中', 'Thinking');
  static String get statusToolCalling => _t('调用工具', 'Calling tool');
  static String get statusError => _t('错误', 'Error');
```

- [ ] **Step 2: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add client/lib/l10n/strings.dart
git commit -m "feat(client): add i18n strings for Office visualization"
```

---

### Task 7: Client — Office visualization (CustomPainter + screen)

**Files:**
- Create: `client/lib/widgets/office_painter.dart`
- Create: `client/lib/screens/office_screen.dart`

- [ ] **Step 1: Create office_painter.dart**

Create `client/lib/widgets/office_painter.dart`:

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/agent_status.dart';

/// Colors for each provider.
Color providerColor(String provider) {
  switch (provider) {
    case 'claude-code':
    case 'claude':
      return const Color(0xFF7C7CFF);
    case 'gemini':
    case 'gemini-cli':
      return const Color(0xFF4285F4);
    case 'opencode':
      return const Color(0xFF00BCD4);
    case 'codex':
      return const Color(0xFF4CD137);
    default:
      return const Color(0xFF9E9E9E);
  }
}

/// Status ring color.
Color statusColor(String status) {
  switch (status) {
    case 'idle':
      return const Color(0xFF22C55E);
    case 'working':
      return const Color(0xFFA855F7);
    case 'thinking':
      return const Color(0xFF3B82F6);
    case 'tool_calling':
      return const Color(0xFFF97316);
    case 'error':
      return const Color(0xFFEF4444);
    default:
      return const Color(0xFF22C55E);
  }
}

/// Provider initial letter for avatar.
String providerInitial(String provider) {
  switch (provider) {
    case 'claude-code':
    case 'claude':
      return 'C';
    case 'gemini':
    case 'gemini-cli':
      return 'G';
    case 'opencode':
      return 'O';
    case 'codex':
      return 'X';
    default:
      return '?';
  }
}

/// Slot position for an agent given index and total count.
Offset slotPosition(int index, int total, Size size) {
  final cols = total <= 4 ? total : (total <= 8 ? 4 : (total / 3).ceil());
  final rows = (total / cols).ceil();
  final slotW = size.width / cols;
  final slotH = size.height / rows;
  final row = index ~/ cols;
  final col = index % cols;
  return Offset(
    col * slotW + slotW / 2,
    row * slotH + slotH / 2,
  );
}

/// Paints the office floor grid.
class OfficePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1;

    // Draw grid
    const spacing = 40.0;
    for (var x = 0.0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Paints a single agent: avatar circle, status ring, name label, activity bubble.
class AgentPainter extends CustomPainter {
  final AgentStatusInfo agent;
  final double animationValue; // 0.0 - 1.0 for status ring animation

  AgentPainter({required this.agent, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 10);
    const avatarRadius = 28.0;

    // Desk outline below avatar
    final deskRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center.translate(0, avatarRadius + 14),
        width: 70,
        height: 12,
      ),
      const Radius.circular(4),
    );
    final deskPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(deskRect, deskPaint);

    // Avatar circle
    final avatarPaint = Paint()
      ..color = providerColor(agent.provider)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, avatarRadius, avatarPaint);

    // Provider initial letter
    final textPainter = TextPainter(
      text: TextSpan(
        text: providerInitial(agent.provider),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );

    // Status ring
    final ringColor = statusColor(agent.status);
    double ringOpacity = 1.0;
    if (agent.status == 'working' || agent.status == 'thinking') {
      ringOpacity = 0.4 + 0.6 * ((math.sin(animationValue * math.pi * 2) + 1) / 2);
    } else if (agent.status == 'error') {
      ringOpacity = animationValue > 0.5 ? 1.0 : 0.2;
    }

    final ringPaint = Paint()
      ..color = ringColor.withValues(alpha: ringOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    if (agent.status == 'tool_calling') {
      // Dashed rotating ring
      final dashPath = Path()
        ..addArc(
          Rect.fromCircle(center: center, radius: avatarRadius + 4),
          animationValue * math.pi * 2,
          math.pi * 1.5,
        );
      canvas.drawPath(dashPath, ringPaint);
    } else {
      canvas.drawCircle(center, avatarRadius + 4, ringPaint);
    }

    // Name label
    final namePainter = TextPainter(
      text: TextSpan(
        text: agent.name,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.8),
          fontSize: 11,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    namePainter.paint(
      canvas,
      Offset(center.dx - namePainter.width / 2, center.dy + avatarRadius + 24),
    );

    // Activity bubble (only if non-empty)
    if (agent.activity.isNotEmpty) {
      final bubblePainter = TextPainter(
        text: TextSpan(
          text: agent.activity,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 10,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: 120);

      final bubbleRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx, center.dy - avatarRadius - 22),
          width: bubblePainter.width + 16,
          height: bubblePainter.height + 10,
        ),
        const Radius.circular(8),
      );
      final bubbleBg = Paint()
        ..color = providerColor(agent.provider).withValues(alpha: 0.15);
      final bubbleBorder = Paint()
        ..color = providerColor(agent.provider).withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRRect(bubbleRect, bubbleBg);
      canvas.drawRRect(bubbleRect, bubbleBorder);

      bubblePainter.paint(
        canvas,
        Offset(
          center.dx - bubblePainter.width / 2,
          center.dy - avatarRadius - 22 - bubblePainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant AgentPainter oldDelegate) =>
      oldDelegate.agent.status != agent.status ||
      oldDelegate.agent.activity != agent.activity ||
      oldDelegate.animationValue != agent.status == 'idle'
          ? false
          : true;
}
```

- [ ] **Step 2: Create office_screen.dart**

Create `client/lib/screens/office_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/agent_status.dart';
import '../providers/agent_status_provider.dart';
import '../widgets/office_painter.dart';
import '../l10n/strings.dart';

class OfficeScreen extends ConsumerStatefulWidget {
  const OfficeScreen({super.key});

  @override
  ConsumerState<OfficeScreen> createState() => _OfficeScreenState();
}

class _OfficeScreenState extends ConsumerState<OfficeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agents = ref.watch(agentStatusProvider);
    final agentList = agents.values.toList();

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/home')),
        title: Text(S.office),
      ),
      body: agentList.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.groups_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(S.noAgentsRunning,
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            )
          : AnimatedBuilder(
              animation: _animController,
              builder: (context, _) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    return CustomPaint(
                      painter: OfficePainter(),
                      child: Stack(
                        children: List.generate(agentList.length, (index) {
                          final agent = agentList[index];
                          final pos = slotPosition(
                            index,
                            agentList.length,
                            Size(constraints.maxWidth, constraints.maxHeight),
                          );
                          const slotSize = Size(140, 160);

                          return Positioned(
                            left: pos.dx - slotSize.width / 2,
                            top: pos.dy - slotSize.height / 2,
                            width: slotSize.width,
                            height: slotSize.height,
                            child: GestureDetector(
                              onTap: () =>
                                  context.push('/agent/${agent.sessionId}'),
                              child: CustomPaint(
                                painter: AgentPainter(
                                  agent: agent,
                                  animationValue: _animController.value,
                                ),
                                size: slotSize,
                              ),
                            ),
                          );
                        }),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
```

- [ ] **Step 3: Verify Flutter analysis**

Run: `cd /Users/zhouwei/Projects/ai/relais/client && flutter analyze lib/widgets/office_painter.dart lib/screens/office_screen.dart 2>&1 | tail -5`

- [ ] **Step 4: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add client/lib/widgets/office_painter.dart client/lib/screens/office_screen.dart
git commit -m "feat(client): add 2D Office visualization with CustomPainter"
```

---

### Task 8: Client — Navigation entry + route

**Files:**
- Modify: `client/lib/screens/home_screen.dart`
- Modify: `client/lib/app.dart`

- [ ] **Step 1: Add route in app.dart**

In `client/lib/app.dart`, add import:

```dart
import 'screens/office_screen.dart';
```

Add route after the `/settings` route:

```dart
    GoRoute(
      path: '/office',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: const ValueKey('office'),
        child: const OfficeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    ),
```

- [ ] **Step 2: Add Office button to HomeScreen AppBar**

In `client/lib/screens/home_screen.dart`, add an Office IconButton in the AppBar `actions` list, before the refresh button:

```dart
          IconButton(
            icon: const Icon(Icons.grid_view),
            tooltip: S.office,
            onPressed: () => context.push('/office'),
          ),
```

Add import at top:

```dart
import '../l10n/strings.dart';
```

(Check if `strings.dart` is already imported — it is, based on the current file.)

- [ ] **Step 3: Verify Flutter analysis**

Run: `cd /Users/zhouwei/Projects/ai/relais/client && flutter analyze lib/app.dart lib/screens/home_screen.dart 2>&1 | tail -5`

- [ ] **Step 4: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add client/lib/app.dart client/lib/screens/home_screen.dart
git commit -m "feat(client): add Office route and navigation button"
```

---

### Task 9: Integration build + verification

**Files:** None (verification only)

- [ ] **Step 1: Build the server**

Run: `cd /Users/zhouwei/Projects/ai/relais/server && cargo build 2>&1 | tail -5`

- [ ] **Step 2: Analyze the client**

Run: `cd /Users/zhouwei/Projects/ai/relais/client && flutter analyze 2>&1 | tail -10`

- [ ] **Step 3: Manual test**

1. Start server: `make server-dev`
2. Connect Flutter client
3. Create 2-3 agent sessions
4. Tap the grid icon in Home AppBar → verify Office screen opens
5. Verify agent avatars appear with correct provider colors
6. Send messages to agents → verify status rings and activity bubbles update
7. Tap an avatar → verify navigation to agent chat screen
8. Kill an agent → verify it disappears from Office view
