# Multi-Agent Office Visualization — Phase 1

**Date:** 2026-03-28
**Status:** Approved
**Scope:** Agent status aggregation (server) + 2D office visualization panel (client)
**Phase:** 1 of 3 (Phase 2: @ task dispatch, Phase 3: full dashboard)

## Overview

Add a gamified 2D "Office" visualization panel where all running agents appear as avatars in a virtual workspace. Each avatar shows the agent's real-time status (idle, working, thinking, etc.) via animated status rings and speech bubbles displaying current activity. Server maintains aggregated status; client is purely presentational.

Reference: [OpenClaw Office 2D](https://github.com/ww-ai-lab/openclaw-office) — SVG top-down office with agent avatars, status indicators, and activity bubbles.

## Design

### 1. Server — Agent Status Registry

#### 1.1 AgentStatusRegistry

**New file:** `server/crates/core/src/agent/status_registry.rs`

A shared data structure maintaining aggregated status for all active agents:

```rust
pub struct AgentStatusEntry {
    pub session_id: String,
    pub name: String,
    pub provider: String,
    pub status: AgentActivity,
    pub activity: String,
    pub cost_usd: Option<f64>,
    pub updated_at: Instant,
}

pub enum AgentActivity {
    Idle,
    Working,
    Thinking,
    ToolCalling,
    Error,
}
```

The registry is a `DashMap<String, AgentStatusEntry>` (same concurrency primitive used by `AgentManager`).

#### 1.2 Status Derivation

The existing event router in `manager.rs` already processes all `AgentEvent`s. Add status updates to the registry alongside the existing EventBus publish:

| AgentEvent | → AgentActivity | activity text |
|-----------|-----------------|---------------|
| `Text(content)` | Working | First 50 chars of content |
| `Thinking(content)` | Thinking | "Thinking..." |
| `ToolUse { name, .. }` | ToolCalling | "Using: {name}" |
| `ToolResult { .. }` | Working | "Processing result..." |
| `TurnComplete { cost_usd, .. }` | Idle | "" (clear), accumulate cost |
| `Error(msg)` | Error | First 80 chars of msg |
| `UserMessage { .. }` | Working | "Processing message..." |

Registry entries are created when an agent session starts and removed when it's killed.

#### 1.3 REST API

**Endpoint:** `GET /api/v1/agents/status`

**Response:**
```json
[
  {
    "session_id": "abc123",
    "name": "main",
    "provider": "claude-code",
    "status": "working",
    "activity": "Editing auth.ts",
    "cost_usd": 0.12
  },
  {
    "session_id": "def456",
    "name": "test-runner",
    "provider": "gemini",
    "status": "idle",
    "activity": "",
    "cost_usd": 0.03
  }
]
```

#### 1.4 WebSocket Status Broadcast

Extend the existing `ControlEvent::AgentStatusChanged` to include activity information. The `/ws/status` WebSocket already broadcasts control events; the office panel subscribes to receive real-time updates.

Add a new control event variant:

```rust
ControlEvent::AgentActivityChanged {
    session_id: SessionId,
    status: String,      // "idle", "working", "thinking", "tool_calling", "error"
    activity: String,    // human-readable summary
}
```

Throttle: emit at most once per second per agent to avoid flooding.

### 2. Client — Data Layer

#### 2.1 AgentStatusInfo Model

**New file:** `client/lib/models/agent_status.dart`

```dart
class AgentStatusInfo {
  final String sessionId;
  final String name;
  final String provider;
  final String status;
  final String activity;
  final double? costUsd;
}
```

#### 2.2 AgentStatusProvider

**New file:** `client/lib/providers/agent_status_provider.dart`

A Riverpod provider managing the global agent status map:

- On Office screen mount: call `GET /api/v1/agents/status` for initial snapshot
- Subscribe to `/ws/status` for `AgentActivityChanged` events
- Expose `Map<String, AgentStatusInfo>` to UI
- Independent of `AgentSession` (which manages per-session chat)

### 3. Client — Office Visualization

#### 3.1 OfficeScreen

**New file:** `client/lib/screens/office_screen.dart`

Scaffold with AppBar ("Office") and full-screen body containing the office canvas. Watches `AgentStatusProvider` for data.

#### 3.2 Office Canvas (CustomPainter)

**New file:** `client/lib/widgets/office_painter.dart`

A `CustomPainter` that renders:

**Background layer:**
- Soft grid floor pattern (light lines on dark background)
- Subtle zone boundary (just a dashed rectangle or nothing for Phase 1)

**Agent layer (per agent):**
- **Workstation outline:** Simple desk shape (rounded rectangle) below the avatar
- **Avatar circle:** 60px diameter, filled with provider color
  - Claude: `#7c7cff` (purple)
  - Gemini: `#4285f4` (blue)
  - OpenCode: `#00bcd4` (cyan)
  - Codex: `#4cd137` (green)
- **Provider icon:** First letter of provider name centered in avatar, white, bold
- **Status ring:** 3px stroke around avatar, animated:
  - Idle: green (`#22c55e`), static
  - Working: purple (`#a855f7`), pulsing opacity
  - Thinking: blue (`#3b82f6`), breathing (scale pulse)
  - ToolCalling: orange (`#f97316`), dashed rotating
  - Error: red (`#ef4444`), blinking
- **Name label:** Below avatar, centered, small text
- **Activity bubble:** Above avatar, rounded rectangle with text, only shown when activity is non-empty. Fade in/out on change.

**Layout algorithm:**
- Available space divided into slots
- ≤4 agents: single centered row
- 5-8 agents: 2 rows
- 9+ agents: 3 rows, scrollable
- Each slot is ~120x140px (desk + avatar + label + bubble)

#### 3.3 Animations

**New file:** `client/lib/widgets/office_agent.dart`

Uses `AnimationController` + `CustomPainter` for per-agent animations:

- Status ring animations driven by `AnimationController` with appropriate curves
- Activity bubble fade: `CurvedAnimation` with `Curves.easeInOut`
- All animations are lightweight (opacity/stroke changes only, no complex transforms)

#### 3.4 Interaction

- **Tap agent avatar** → Navigate to `/agent/:sessionId` (existing agent chat screen)
- **Long press** → Show tooltip with full status details (provider, model, cost, uptime)

### 4. Navigation Entry

**Modify:** `client/lib/screens/home_screen.dart`

Add an IconButton to the AppBar `actions`:

```dart
IconButton(
  icon: const Icon(Icons.grid_view),
  tooltip: 'Office',
  onPressed: () => context.go('/office'),
)
```

**Modify:** `client/lib/app.dart`

Add route:

```dart
GoRoute(path: '/office', builder: (_, __) => const OfficeScreen())
```

## Out of Scope (Phase 1)

- Right sidebar (agent list, event timeline)
- Chat input in office view
- Sub-agent badges and connection lines
- Walking animations / agent movement
- Theme switching (medieval, cyberpunk, etc.)
- Furniture drag-and-drop / custom layout
- `@` task dispatch (Phase 2)
- Agent topology graph (Phase 3)

## Files Changed

| File | Action | Purpose |
|------|--------|---------|
| `server/crates/core/src/agent/status_registry.rs` | Create | AgentStatusRegistry with DashMap |
| `server/crates/core/src/agent/manager.rs` | Modify | Update registry on agent events, throttle |
| `server/crates/core/src/agent/mod.rs` | Modify | Export status_registry module |
| `server/crates/core/src/events.rs` | Modify | Add `AgentActivityChanged` control event |
| `server/crates/server/src/api/` | Modify | Add `GET /api/v1/agents/status` handler |
| `server/crates/server/src/ws/status.rs` | Modify | Serialize `AgentActivityChanged` events |
| `client/lib/models/agent_status.dart` | Create | AgentStatusInfo model |
| `client/lib/providers/agent_status_provider.dart` | Create | Global agent status provider |
| `client/lib/screens/office_screen.dart` | Create | Office page scaffold |
| `client/lib/widgets/office_painter.dart` | Create | 2D floor + workstation CustomPainter |
| `client/lib/widgets/office_agent.dart` | Create | Agent avatar + status ring + bubble |
| `client/lib/screens/home_screen.dart` | Modify | Add Office icon button to AppBar |
| `client/lib/app.dart` | Modify | Add /office route |
| `client/lib/l10n/strings.dart` | Modify | Add Office-related i18n strings |

## Testing

1. **Server:** Unit test for status derivation logic (AgentEvent → AgentActivity mapping)
2. **Server:** Integration test for REST endpoint (returns correct agent list)
3. **Client:** Widget test for OfficeScreen (renders agents from mock data)
4. **Manual:** Start 2-3 agents, open Office view, verify avatars appear with correct status, click to navigate to chat
