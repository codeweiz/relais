# Slash Commands for Agent Screen

**Date:** 2026-03-28
**Status:** Approved
**Scope:** Agent chat slash command discovery, rendering, and execution

## Overview

Enable slash command support in the agent chat screen. Users type `/` to see available commands, filter by typing, select a command, and execute it. Commands are discovered dynamically via the ACP protocol's `AvailableCommandsUpdate` notification — no static registry or text parsing needed.

## Background

### Current State

- **Server:** Messages starting with `/` are routed to `write_stdin()` (manager.rs:200-203), which sends them as ACP prompts. Slash commands reach the agent CLI and execute correctly.
- **Client:** No slash command UI. No autocomplete, no command menu, no visual hints.
- **ACP Protocol:** The Rust crate `agent-client-protocol-schema` v0.11.3 defines `AvailableCommandsUpdate` with `Vec<AvailableCommand>`, where each command has `name`, `description`, and optional `input` spec. Agents (Claude Code, Gemini, etc.) push this notification after session initialization.
- **Gap:** Relais's `acp_backend.rs` drops `AvailableCommandsUpdate` in a catch-all `_ => {}` handler (line 465).

### Key Discovery

Testing confirmed that `/help` and other slash commands return no text via ACP — they are handled silently by the agent's TUI layer. However, the ACP protocol natively supports command discovery through `AvailableCommandsUpdate`. Mitto (a Go-based ACP client) already uses this mechanism successfully.

## Design

### 1. Server — Data Flow

The server has a three-layer event pipeline: `AgentEvent` → `DataEvent` → WebSocket JSON. All three layers need a new variant.

#### 1.1 AgentEvent (ACP backend emits)

**File:** `server/crates/core/src/agent/event.rs`

```rust
#[derive(Debug, Clone)]
pub struct SlashCommandInfo {
    pub name: String,
    pub description: String,
}

pub enum AgentEvent {
    // ... existing variants ...
    /// Available slash commands pushed by the agent.
    AvailableCommands(Vec<SlashCommandInfo>),
}
```

#### 1.2 ACP notification handler

**File:** `server/crates/core/src/agent/acp_backend.rs` (in `session_notification`, replacing the `_ => {}` catch-all)

```rust
SessionUpdate::AvailableCommandsUpdate(update) => {
    let commands: Vec<SlashCommandInfo> = update
        .available_commands
        .iter()
        .map(|cmd| SlashCommandInfo {
            name: cmd.name.strip_prefix('/').unwrap_or(&cmd.name).to_string(),
            description: cmd.description.clone(),
        })
        .collect();
    let _ = self.event_tx.send(AgentEvent::AvailableCommands(commands));
}
```

#### 1.3 DataEvent (EventBus transport)

**File:** `server/crates/core/src/events.rs`

```rust
pub enum DataEvent {
    // ... existing variants ...
    /// Available slash commands from the agent (no seq — not part of turn sequence).
    AgentAvailableCommands {
        commands: Vec<(String, String)>, // (name, description)
    },
}
```

Note: no `seq` field — this is a metadata push, not a conversation event. It should NOT be stored in event history for replay.

#### 1.4 Event conversion

**File:** `server/crates/core/src/agent/manager.rs` (in `agent_event_to_data_event`)

```rust
AgentEvent::AvailableCommands(cmds) => DataEvent::AgentAvailableCommands {
    commands: cmds.iter().map(|c| (c.name.clone(), c.description.clone())).collect(),
},
```

The event routing loop in `manager.rs` should broadcast this event but NOT append it to the event history Vec (since it's not a conversation event).

#### 1.5 WebSocket serialization

**File:** `server/crates/server/src/ws/agent.rs`

Add handling in both `handle_agent` (live events) and `data_event_to_json` (replay):

```json
{
  "type": "available_commands",
  "commands": [
    { "name": "compact", "description": "Compact conversation history" },
    { "name": "model", "description": "Switch AI model" },
    { "name": "help", "description": "Show available commands" }
  ]
}
```

Command names are normalized by the server: leading `/` stripped if present, so the client always receives bare names. The client prepends `/` when displaying and executing.

### 3. Client — Data Layer (Flutter/Dart)

#### 3.1 SlashCommand Model

**New file:** `client/lib/models/slash_command.dart`

```dart
class SlashCommand {
  final String name;
  final String description;

  const SlashCommand({required this.name, required this.description});

  factory SlashCommand.fromJson(Map<String, dynamic> json) => SlashCommand(
    name: json['name'] as String,
    description: json['description'] as String,
  );
}
```

#### 3.2 AgentConnection Changes

**File:** `client/lib/services/agent_connection.dart`

- Add `StreamController<List<SlashCommand>>` for command updates
- In the WebSocket message handler, detect `type: "available_commands"` and parse into `List<SlashCommand>`
- Expose `Stream<List<SlashCommand>> get slashCommands`

#### 3.3 AgentSession Changes

**File:** `client/lib/providers/agent_provider.dart`

- Add `List<SlashCommand>? _cachedCommands` — session-level cache
- Subscribe to `connection.slashCommands` and update cache on each push
- Expose `List<SlashCommand>? get availableCommands` for the UI
- Clear cache when connection status becomes `disconnected`

### 4. Client — UI Layer (Flutter)

#### 4.1 SlashCommandMenu Widget

**New file:** `client/lib/widgets/slash_command_menu.dart`

A widget that displays filtered slash commands. Renders differently per platform:

**Desktop (OverlayEntry above TextField):**
- Compact list: each row shows `/name` (bold) + description (muted)
- Highlight matching prefix text
- Max visible items: 8, scrollable
- Keyboard navigation: ↑↓ to move selection, Enter to confirm, Esc to dismiss
- Positioned directly above the input field using `LayerLink` + `CompositedTransformFollower`

**Mobile (BottomSheet):**
- `showModalBottomSheet` with drag handle
- Each row: `/name` + description, min height 48dp for touch targets
- Tap to select
- Search input at top of sheet for additional filtering

**Platform detection:** Use `defaultTargetPlatform` — iOS/Android → BottomSheet, macOS/Windows/Linux/Web → Overlay.

**Filtering logic:**
- Input: current text after `/` (e.g., user typed `/com` → filter string is `com`)
- Match: prefix match on command name (`com` matches `compact`, `commit`)
- Sort: exact prefix matches first, then alphabetical
- Empty filter (just `/`): show all commands

#### 4.2 AgentScreen Integration

**File:** `client/lib/screens/agent_screen.dart`

Changes to the existing screen:

1. Add `onChanged` callback to TextField to detect `/` prefix
2. When text starts with `/` and commands are cached → show SlashCommandMenu
3. When text doesn't start with `/` or is empty → dismiss menu
4. On command selection callback:
   - Set TextField text to `/<commandName> ` (with trailing space)
   - Move cursor to end
   - Dismiss menu
   - Do NOT auto-send — user may want to append arguments
5. On Enter/send: existing `_sendMessage()` flow handles it (server already routes `/` messages)

### 5. Command Execution Flow

No changes needed. The existing flow already works:

1. User sends message starting with `/` → `AgentConnection.sendMessage(text)`
2. Server receives → `manager.rs` detects `/` prefix → routes to `write_stdin()`
3. Agent CLI processes the slash command
4. Response flows back through normal ACP event stream

### 6. Caching Strategy

- **Source:** Agent pushes `AvailableCommandsUpdate` after session initialization, and again whenever the command list changes (e.g., skills installed/uninstalled)
- **Storage:** In-memory on `AgentSession`, per-session
- **Update:** Each push fully replaces the cached list (not incremental)
- **Invalidation:** Cache cleared when connection status becomes `disconnected`
- **First `/` before cache populated:** Show a brief loading indicator in the menu. Commands appear as soon as the agent pushes them (typically within seconds of session start).

### 7. Error Handling

- **Agent doesn't support AvailableCommandsUpdate:** Menu shows empty state with text "No commands available". User can still type and send slash commands manually.
- **Unknown command entered:** Sent to agent as-is. Agent handles the error in its own response. Client does not validate.
- **WebSocket disconnection during menu:** Menu dismissed, reconnection follows existing flow.

## Out of Scope

- **Message style enhancement** — Agent response rendering improvements (separate spec)
- **Chat + Terminal dual mode** — Side-by-side chat and PTY terminal (separate spec)
- **Command argument auto-complete** — No second-level menus for command parameters
- **Client-side command validation** — All commands forwarded to agent unconditionally

## Files Changed

| File | Change |
|------|--------|
| `server/crates/core/src/agent/event.rs` | Add `SlashCommandInfo` struct, `AgentEvent::AvailableCommands` variant |
| `server/crates/core/src/agent/acp_backend.rs` | Handle `AvailableCommandsUpdate` in `session_notification` |
| `server/crates/core/src/events.rs` | Add `DataEvent::AgentAvailableCommands` variant |
| `server/crates/core/src/agent/manager.rs` | Add conversion in `agent_event_to_data_event`, broadcast without storing in history |
| `server/crates/server/src/ws/agent.rs` | Handle + serialize `AgentAvailableCommands` in both live loop and `data_event_to_json` |
| `client/lib/models/slash_command.dart` | **New** — `SlashCommand` model |
| `client/lib/services/agent_connection.dart` | Parse `available_commands` WebSocket messages |
| `client/lib/providers/agent_provider.dart` | Cache commands on `AgentSession` |
| `client/lib/widgets/slash_command_menu.dart` | **New** — Adaptive command menu widget |
| `client/lib/screens/agent_screen.dart` | Wire up `onChanged`, show/hide menu, handle selection |

## Testing Approach

1. **Server unit test:** Verify `AvailableCommandsUpdate` is correctly mapped to `AgentEvent::AvailableCommands` and serialized to the expected JSON
2. **Client widget test:** `SlashCommandMenu` renders correct items, filters by prefix, handles selection callback
3. **Integration test:** Connect to a Claude Code agent session, verify commands arrive and display in the menu
4. **Manual cross-platform test:** Verify overlay on desktop, bottom sheet on mobile, keyboard nav, touch selection
