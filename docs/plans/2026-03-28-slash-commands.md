# Slash Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable slash command discovery, autocomplete menu, and execution in the agent chat screen — commands discovered dynamically from ACP `AvailableCommandsUpdate`.

**Architecture:** Server wires the currently-dropped ACP `AvailableCommandsUpdate` notification through the existing three-layer pipeline (AgentEvent → DataEvent → WebSocket JSON). Client receives structured command list, caches per-session, and renders an adaptive autocomplete menu (overlay on desktop, bottom sheet on mobile).

**Tech Stack:** Rust (server, agent-client-protocol crate), Flutter/Dart (client), WebSocket JSON protocol

**Spec:** `docs/specs/2026-03-28-slash-commands-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `server/crates/core/src/agent/event.rs` | Modify | Add `SlashCommandInfo` struct + `AgentEvent::AvailableCommands` variant |
| `server/crates/core/src/events.rs` | Modify | Add `DataEvent::AgentAvailableCommands` variant |
| `server/crates/core/src/agent/acp_backend.rs` | Modify | Handle `AvailableCommandsUpdate` in `session_notification` |
| `server/crates/core/src/agent/manager.rs` | Modify | Convert new event variant, skip history for it |
| `server/crates/server/src/ws/agent.rs` | Modify | Serialize + broadcast `AgentAvailableCommands` to WebSocket |
| `client/lib/models/slash_command.dart` | Create | `SlashCommand` data model |
| `client/lib/services/agent_connection.dart` | Modify | Parse `available_commands` WebSocket event |
| `client/lib/providers/agent_provider.dart` | Modify | Cache commands on `AgentSession`, clear on disconnect |
| `client/lib/widgets/slash_command_menu.dart` | Create | Adaptive menu widget (overlay / bottom sheet) |
| `client/lib/screens/agent_screen.dart` | Modify | Wire TextField to menu, handle selection |
| `client/lib/l10n/strings.dart` | Modify | Add i18n strings for menu UI |

---

### Task 1: Server — AgentEvent + DataEvent variants

**Files:**
- Modify: `server/crates/core/src/agent/event.rs:59-89`
- Modify: `server/crates/core/src/events.rs:68-122`

- [ ] **Step 1: Add SlashCommandInfo and AgentEvent variant**

In `server/crates/core/src/agent/event.rs`, add after the `AgentKind` impl block (before the `AgentEvent` enum), then add a new variant to the enum:

```rust
/// Metadata about a single slash command.
#[derive(Debug, Clone)]
pub struct SlashCommandInfo {
    pub name: String,
    pub description: String,
}
```

Add to `AgentEvent` enum after `UserMessage`:

```rust
    /// Available slash commands pushed by the agent.
    AvailableCommands(Vec<SlashCommandInfo>),
```

- [ ] **Step 2: Add DataEvent variant**

In `server/crates/core/src/events.rs`, add to `DataEvent` enum after `AgentError`:

```rust
    /// Available slash commands from the agent (no seq — metadata, not conversation).
    AgentAvailableCommands {
        commands: Vec<(String, String)>,
    },
```

- [ ] **Step 3: Verify it compiles**

Run: `cd /Users/zhouwei/Projects/ai/relais/server && cargo check -p relais-core 2>&1 | tail -5`

Expected: Warnings about non-exhaustive match patterns (we'll fix those in Task 2 and 3). No errors.

- [ ] **Step 4: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add server/crates/core/src/agent/event.rs server/crates/core/src/events.rs
git commit -m "feat(server): add AvailableCommands event variants for slash commands"
```

---

### Task 2: Server — ACP notification handler + event conversion

**Files:**
- Modify: `server/crates/core/src/agent/acp_backend.rs:464-465`
- Modify: `server/crates/core/src/agent/manager.rs:287-322` (event router) and `352-398` (conversion fn)

- [ ] **Step 1: Handle AvailableCommandsUpdate in acp_backend.rs**

In `server/crates/core/src/agent/acp_backend.rs`, replace the catch-all `_ => {}` at line 465 with:

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
            _ => {}
```

Add `use crate::agent::event::SlashCommandInfo;` to the imports at the top of the file if not already reachable through the existing `use` of `AgentEvent`.

- [ ] **Step 2: Add conversion in agent_event_to_data_event**

In `server/crates/core/src/agent/manager.rs`, add a new arm to the `match` in `agent_event_to_data_event` (after the `UserMessage` arm, before the closing `}`):

```rust
        AgentEvent::AvailableCommands(cmds) => DataEvent::AgentAvailableCommands {
            commands: cmds
                .iter()
                .map(|c| (c.name.clone(), c.description.clone()))
                .collect(),
        },
```

- [ ] **Step 3: Skip history storage for AvailableCommands**

In `server/crates/core/src/agent/manager.rs`, in the `start_event_router` method (around line 298-309), change the event handling to skip history for `AvailableCommands`:

Replace:

```rust
                    Ok(event) => {
                        // Persist event for replay
                        if let Ok(mut history) = event_history.lock() {
                            history.push(event.clone());
                        }

                        let data_event = agent_event_to_data_event(seq, &event);
                        seq += 1;
                        event_bus.publish_data(&sid, data_event).await;
                    }
```

With:

```rust
                    Ok(event) => {
                        // AvailableCommands is metadata — broadcast but don't persist in history
                        let skip_history = matches!(event, AgentEvent::AvailableCommands(_));
                        if !skip_history {
                            if let Ok(mut history) = event_history.lock() {
                                history.push(event.clone());
                            }
                        }

                        let data_event = agent_event_to_data_event(seq, &event);
                        if !skip_history {
                            seq += 1;
                        }
                        event_bus.publish_data(&sid, data_event).await;
                    }
```

- [ ] **Step 4: Verify it compiles**

Run: `cd /Users/zhouwei/Projects/ai/relais/server && cargo check 2>&1 | tail -5`

Expected: Warnings about unmatched `AgentAvailableCommands` in `ws/agent.rs`. No errors.

- [ ] **Step 5: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add server/crates/core/src/agent/acp_backend.rs server/crates/core/src/agent/manager.rs
git commit -m "feat(server): handle ACP AvailableCommandsUpdate, wire through event pipeline"
```

---

### Task 3: Server — WebSocket serialization

**Files:**
- Modify: `server/crates/server/src/ws/agent.rs:180-300` (handle_agent loop) and `316-395` (data_event_to_json)

- [ ] **Step 1: Add live event handling in handle_agent**

In `server/crates/server/src/ws/agent.rs`, in the `handle_agent` function's event match block, add a new arm before the `Some(_)` catch-all (around line 282):

```rust
                    Some(DataEvent::AgentAvailableCommands { commands }) => {
                        let cmd_json: Vec<serde_json::Value> = commands
                            .iter()
                            .map(|(name, desc)| serde_json::json!({ "name": name, "description": desc }))
                            .collect();
                        let msg = serde_json::json!({
                            "type": "available_commands",
                            "commands": cmd_json,
                        });
                        if ws_tx.send(Message::Text(msg.to_string().into())).await.is_err() {
                            debug!(session_id = %session_id, "failed to send available_commands, closing");
                            break;
                        }
                    }
```

- [ ] **Step 2: Add serialization in data_event_to_json**

In the same file, add a new arm to `data_event_to_json` before the `_ =>` catch-all (around line 393):

```rust
        DataEvent::AgentAvailableCommands { commands } => {
            let cmd_json: Vec<serde_json::Value> = commands
                .iter()
                .map(|(name, desc)| serde_json::json!({ "name": name, "description": desc }))
                .collect();
            serde_json::json!({
                "type": "available_commands",
                "commands": cmd_json,
            })
        }
```

- [ ] **Step 3: Build the full server**

Run: `cd /Users/zhouwei/Projects/ai/relais/server && cargo build 2>&1 | tail -5`

Expected: Clean build with no errors. Warnings are OK.

- [ ] **Step 4: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add server/crates/server/src/ws/agent.rs
git commit -m "feat(server): serialize AvailableCommands to WebSocket JSON"
```

---

### Task 4: Client — SlashCommand model + AgentConnection parsing

**Files:**
- Create: `client/lib/models/slash_command.dart`
- Modify: `client/lib/services/agent_connection.dart`

- [ ] **Step 1: Create SlashCommand model**

Create `client/lib/models/slash_command.dart`:

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

- [ ] **Step 2: Add slash command stream to AgentConnection**

In `client/lib/services/agent_connection.dart`, add the import at the top:

```dart
import '../models/slash_command.dart';
```

Add a new StreamController field inside the `AgentConnection` class (after `_statusController`):

```dart
  final _slashCommandController =
      StreamController<List<SlashCommand>>.broadcast();
```

Add a public getter (after the `status` getter):

```dart
  Stream<List<SlashCommand>> get slashCommands =>
      _slashCommandController.stream;
```

In the `connect()` method's `_channel!.stream.listen` callback, add a handler for `available_commands` after the `status` type check (after `return;` on line 39):

```dart
          if (type == 'available_commands') {
            final rawList = json['commands'] as List<dynamic>;
            final commands = rawList
                .map((c) =>
                    SlashCommand.fromJson(c as Map<String, dynamic>))
                .toList();
            _slashCommandController.add(commands);
            return;
          }
```

In the `dispose()` method, close the new controller (after `_statusController.close()`):

```dart
    _slashCommandController.close();
```

- [ ] **Step 3: Verify Flutter analysis passes**

Run: `cd /Users/zhouwei/Projects/ai/relais/client && flutter analyze lib/models/slash_command.dart lib/services/agent_connection.dart 2>&1 | tail -5`

Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add client/lib/models/slash_command.dart client/lib/services/agent_connection.dart
git commit -m "feat(client): add SlashCommand model and parse available_commands events"
```

---

### Task 5: Client — AgentSession caching

**Files:**
- Modify: `client/lib/providers/agent_provider.dart`

- [ ] **Step 1: Add cache and subscription to AgentSession**

In `client/lib/providers/agent_provider.dart`, add the import at the top:

```dart
import '../models/slash_command.dart';
```

Add fields inside the `AgentSession` class (after `bool waiting = false;`):

```dart
  List<SlashCommand>? _cachedCommands;
  StreamSubscription? _slashCmdSub;
```

Add a public getter (after `waiting`):

```dart
  /// Cached slash commands from the agent, or null if not yet received.
  List<SlashCommand>? get availableCommands => _cachedCommands;
```

In the `factory AgentSession.connect` method, add a subscription after the `_statusSub` setup (after `session._statusSub = connection.status.listen(...)` block, around line 68):

```dart
    session._slashCmdSub = connection.slashCommands.listen((commands) {
      session._cachedCommands = commands;
      session._notify();
    });
```

In the same `_statusSub` listener, clear cache on disconnect. Change:

```dart
    session._statusSub = connection.status.listen((s) {
      session.status = s;
      session._notify();
    });
```

To:

```dart
    session._statusSub = connection.status.listen((s) {
      session.status = s;
      if (s == 'disconnected') {
        session._cachedCommands = null;
      }
      session._notify();
    });
```

In the `dispose()` method, cancel the new subscription (after `_statusSub?.cancel()`):

```dart
    _slashCmdSub?.cancel();
```

- [ ] **Step 2: Verify Flutter analysis passes**

Run: `cd /Users/zhouwei/Projects/ai/relais/client && flutter analyze lib/providers/agent_provider.dart 2>&1 | tail -5`

Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add client/lib/providers/agent_provider.dart
git commit -m "feat(client): cache slash commands in AgentSession, clear on disconnect"
```

---

### Task 6: Client — i18n strings

**Files:**
- Modify: `client/lib/l10n/strings.dart`

- [ ] **Step 1: Add slash command menu strings**

In `client/lib/l10n/strings.dart`, add before the `_t` helper method:

```dart
  static String get noCommandsAvailable => _t('暂无可用命令', 'No commands available');
  static String get loadingCommands => _t('加载命令中...', 'Loading commands...');
  static String get slashCommandHint => _t('输入筛选命令...', 'Filter commands...');
```

- [ ] **Step 2: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add client/lib/l10n/strings.dart
git commit -m "feat(client): add i18n strings for slash command menu"
```

---

### Task 7: Client — SlashCommandMenu widget (Desktop overlay)

**Files:**
- Create: `client/lib/widgets/slash_command_menu.dart`

- [ ] **Step 1: Create the adaptive SlashCommandMenu widget**

Create `client/lib/widgets/slash_command_menu.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import '../models/slash_command.dart';
import '../l10n/strings.dart';

/// Filters [commands] by prefix-matching [filter] against command names.
/// Returns all commands if [filter] is empty.
List<SlashCommand> filterCommands(List<SlashCommand> commands, String filter) {
  if (filter.isEmpty) return List.of(commands);
  final lower = filter.toLowerCase();
  final matched =
      commands.where((c) => c.name.toLowerCase().startsWith(lower)).toList();
  matched.sort((a, b) => a.name.compareTo(b.name));
  return matched;
}

/// Whether the current platform should use a bottom sheet (mobile) or overlay (desktop).
bool get _isMobilePlatform {
  final p = defaultTargetPlatform;
  return p == TargetPlatform.iOS || p == TargetPlatform.android;
}

/// Shows the slash command menu. On desktop, manages an [OverlayEntry] above
/// [layerLink]. On mobile, calls [showModalBottomSheet].
///
/// Use [SlashCommandMenuController] to manage lifecycle.
class SlashCommandMenuController {
  OverlayEntry? _overlayEntry;
  int _selectedIndex = 0;

  /// Show the command menu. Call this when the user types "/".
  void show({
    required BuildContext context,
    required LayerLink layerLink,
    required List<SlashCommand> commands,
    required String filter,
    required ValueChanged<SlashCommand> onSelect,
    required VoidCallback onDismiss,
  }) {
    if (_isMobilePlatform) {
      _showBottomSheet(
        context: context,
        commands: commands,
        filter: filter,
        onSelect: onSelect,
        onDismiss: onDismiss,
      );
      return;
    }

    // Desktop: overlay
    _selectedIndex = 0;
    _removeOverlay();

    _overlayEntry = OverlayEntry(
      builder: (_) => _DesktopOverlay(
        layerLink: layerLink,
        commands: filterCommands(commands, filter),
        selectedIndex: _selectedIndex,
        onSelect: (cmd) {
          _removeOverlay();
          onSelect(cmd);
        },
        onDismiss: () {
          _removeOverlay();
          onDismiss();
        },
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  /// Update the filter text while the menu is visible (desktop only).
  void updateFilter({
    required BuildContext context,
    required LayerLink layerLink,
    required List<SlashCommand> commands,
    required String filter,
    required ValueChanged<SlashCommand> onSelect,
    required VoidCallback onDismiss,
  }) {
    if (_isMobilePlatform || _overlayEntry == null) return;
    final filtered = filterCommands(commands, filter);
    if (_selectedIndex >= filtered.length) {
      _selectedIndex = filtered.isEmpty ? 0 : filtered.length - 1;
    }
    _overlayEntry!.markNeedsBuild();
    // Rebuild with new data
    _removeOverlay();
    _overlayEntry = OverlayEntry(
      builder: (_) => _DesktopOverlay(
        layerLink: layerLink,
        commands: filtered,
        selectedIndex: _selectedIndex,
        onSelect: (cmd) {
          _removeOverlay();
          onSelect(cmd);
        },
        onDismiss: () {
          _removeOverlay();
          onDismiss();
        },
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  /// Handle keyboard events. Returns true if consumed.
  bool handleKey(KeyEvent event, List<SlashCommand> filteredCommands,
      ValueChanged<SlashCommand> onSelect, VoidCallback onDismiss) {
    if (_isMobilePlatform || _overlayEntry == null) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (filteredCommands.isNotEmpty) {
        _selectedIndex = (_selectedIndex + 1) % filteredCommands.length;
        _overlayEntry!.markNeedsBuild();
      }
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (filteredCommands.isNotEmpty) {
        _selectedIndex =
            (_selectedIndex - 1 + filteredCommands.length) % filteredCommands.length;
        _overlayEntry!.markNeedsBuild();
      }
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _removeOverlay();
      onDismiss();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      if (filteredCommands.isNotEmpty &&
          _selectedIndex < filteredCommands.length) {
        final cmd = filteredCommands[_selectedIndex];
        _removeOverlay();
        onSelect(cmd);
        return true;
      }
    }
    return false;
  }

  /// Whether the overlay is currently showing.
  bool get isVisible => _overlayEntry != null;

  /// Remove the overlay if visible.
  void dismiss() => _removeOverlay();

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showBottomSheet({
    required BuildContext context,
    required List<SlashCommand> commands,
    required String filter,
    required ValueChanged<SlashCommand> onSelect,
    required VoidCallback onDismiss,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _MobileBottomSheet(
        commands: commands,
        initialFilter: filter,
        onSelect: (cmd) {
          Navigator.of(ctx).pop();
          onSelect(cmd);
        },
      ),
    ).whenComplete(onDismiss);
  }
}

// ---------------------------------------------------------------------------
// Desktop overlay widget
// ---------------------------------------------------------------------------

class _DesktopOverlay extends StatelessWidget {
  final LayerLink layerLink;
  final List<SlashCommand> commands;
  final int selectedIndex;
  final ValueChanged<SlashCommand> onSelect;
  final VoidCallback onDismiss;

  const _DesktopOverlay({
    required this.layerLink,
    required this.commands,
    required this.selectedIndex,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = 8 * 40.0; // 8 items * 40px

    return CompositedTransformFollower(
      link: layerLink,
      showWhenUnlinked: false,
      targetAnchor: Alignment.topLeft,
      followerAnchor: Alignment.bottomLeft,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerHighest,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 400),
          child: commands.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(S.noCommandsAvailable,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: commands.length,
                  itemBuilder: (context, index) {
                    final cmd = commands[index];
                    final isSelected = index == selectedIndex;
                    return InkWell(
                      onTap: () => onSelect(cmd),
                      child: Container(
                        color: isSelected
                            ? theme.colorScheme.primary.withOpacity(0.12)
                            : null,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Text(
                              '/${cmd.name}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                cmd.description,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mobile bottom sheet
// ---------------------------------------------------------------------------

class _MobileBottomSheet extends StatefulWidget {
  final List<SlashCommand> commands;
  final String initialFilter;
  final ValueChanged<SlashCommand> onSelect;

  const _MobileBottomSheet({
    required this.commands,
    required this.initialFilter,
    required this.onSelect,
  });

  @override
  State<_MobileBottomSheet> createState() => _MobileBottomSheetState();
}

class _MobileBottomSheetState extends State<_MobileBottomSheet> {
  late final TextEditingController _filterController;
  late List<SlashCommand> _filtered;

  @override
  void initState() {
    super.initState();
    _filterController = TextEditingController(text: widget.initialFilter);
    _filtered = filterCommands(widget.commands, widget.initialFilter);
    _filterController.addListener(_onFilterChanged);
  }

  void _onFilterChanged() {
    setState(() {
      _filtered = filterCommands(widget.commands, _filterController.text);
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxH = MediaQuery.of(context).size.height * 0.5;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Filter input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              controller: _filterController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: S.slashCommandHint,
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Command list
          Flexible(
            child: _filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(S.noCommandsAvailable,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final cmd = _filtered[index];
                      return ListTile(
                        dense: false,
                        visualDensity: VisualDensity.standard,
                        title: Text(
                          '/${cmd.name}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        subtitle: Text(cmd.description),
                        onTap: () => widget.onSelect(cmd),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify Flutter analysis passes**

Run: `cd /Users/zhouwei/Projects/ai/relais/client && flutter analyze lib/widgets/slash_command_menu.dart 2>&1 | tail -10`

Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add client/lib/widgets/slash_command_menu.dart
git commit -m "feat(client): add adaptive SlashCommandMenu widget"
```

---

### Task 8: Client — Wire AgentScreen to SlashCommandMenu

**Files:**
- Modify: `client/lib/screens/agent_screen.dart`

- [ ] **Step 1: Add imports and state fields**

In `client/lib/screens/agent_screen.dart`, add imports:

```dart
import '../models/slash_command.dart';
import '../widgets/slash_command_menu.dart';
```

Add fields to `_AgentScreenState` (after `bool _isListening = false;`):

```dart
  final _layerLink = LayerLink();
  final _menuController = SlashCommandMenuController();
  bool _showingMenu = false;
```

- [ ] **Step 2: Add onChanged handler and menu trigger**

Add a method to `_AgentScreenState`:

```dart
  @override
  void dispose() {
    _menuController.dismiss();
    _speech.stop();
    _session?.removeListener(_onUpdate);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onInputChanged(String text) {
    final session = _session;
    if (session == null) return;

    if (text.startsWith('/') && !text.contains(' ')) {
      final filter = text.substring(1); // strip leading "/"
      final commands = session.availableCommands;

      if (commands == null) {
        // Commands not yet received — don't show menu
        return;
      }

      if (!_showingMenu) {
        _showingMenu = true;
        _menuController.show(
          context: context,
          layerLink: _layerLink,
          commands: commands,
          filter: filter,
          onSelect: _onCommandSelected,
          onDismiss: _onMenuDismissed,
        );
      } else {
        _menuController.updateFilter(
          context: context,
          layerLink: _layerLink,
          commands: commands,
          filter: filter,
          onSelect: _onCommandSelected,
          onDismiss: _onMenuDismissed,
        );
      }
    } else {
      _dismissMenu();
    }
  }

  void _onCommandSelected(SlashCommand cmd) {
    _inputController.text = '/${cmd.name} ';
    _inputController.selection = TextSelection.collapsed(
      offset: _inputController.text.length,
    );
    _showingMenu = false;
  }

  void _onMenuDismissed() {
    _showingMenu = false;
  }

  void _dismissMenu() {
    if (_showingMenu) {
      _menuController.dismiss();
      _showingMenu = false;
    }
  }
```

- [ ] **Step 3: Add menu dismiss to _sendMessage**

In `_sendMessage()`, add `_dismissMenu();` as the first line (before the `final text = ...` line):

```dart
  void _sendMessage() {
    _dismissMenu();
    final text = _inputController.text.trim();
    // ... rest unchanged
  }
```

- [ ] **Step 4: Replace the dispose method**

The full `dispose()` override is already included in the `_onInputChanged` step above — it replaces the existing one by adding `_menuController.dismiss()`.

- [ ] **Step 5: Wire TextField with LayerLink and onChanged**

In the `build` method, wrap the `TextField` with a `CompositedTransformTarget` and add `onChanged`:

Replace the existing TextField block:

```dart
                    child: TextField(
                      controller: _inputController,
                      decoration: InputDecoration(
                        hintText: S.sendMessage,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                      textInputAction: TextInputAction.send,
                    ),
```

With:

```dart
                    child: CompositedTransformTarget(
                      link: _layerLink,
                      child: TextField(
                        controller: _inputController,
                        decoration: InputDecoration(
                          hintText: S.sendMessage,
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          isDense: true,
                        ),
                        onChanged: _onInputChanged,
                        onSubmitted: (_) {
                          _dismissMenu();
                          _sendMessage();
                        },
                        textInputAction: TextInputAction.send,
                      ),
                    ),
```

- [ ] **Step 6: Verify Flutter analysis passes**

Run: `cd /Users/zhouwei/Projects/ai/relais/client && flutter analyze lib/screens/agent_screen.dart 2>&1 | tail -10`

Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add client/lib/screens/agent_screen.dart
git commit -m "feat(client): wire agent screen to slash command menu"
```

---

### Task 9: Integration build + manual verification

**Files:** None (verification only)

- [ ] **Step 1: Build the server**

Run: `cd /Users/zhouwei/Projects/ai/relais/server && cargo build 2>&1 | tail -5`

Expected: Clean build.

- [ ] **Step 2: Build the Flutter client**

Run: `cd /Users/zhouwei/Projects/ai/relais/client && flutter build macos 2>&1 | tail -10`

Expected: Clean build (or `flutter build apk` / `flutter run` depending on target platform).

- [ ] **Step 3: Manual integration test**

1. Start the server: `make server-dev`
2. Connect from the Flutter client
3. Create a Claude Code agent session
4. Wait for connection (green dot)
5. Type `/` in the input field
6. Verify: command menu appears with commands (if Claude Code pushes `AvailableCommandsUpdate`)
7. Type `/com` — verify filtering works
8. Select a command — verify it fills the input with `/<name> `
9. Press Enter — verify command is sent and agent processes it

- [ ] **Step 4: Final commit with all changes**

If any fixes were needed during testing, commit them:

```bash
cd /Users/zhouwei/Projects/ai/relais
git add -A
git commit -m "feat: slash command discovery and autocomplete menu

Wire ACP AvailableCommandsUpdate through server event pipeline to
client. Adaptive UI: overlay on desktop, bottom sheet on mobile."
```
