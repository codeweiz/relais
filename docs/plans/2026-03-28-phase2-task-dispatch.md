# Phase 2: @ Task Dispatch + Office Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable @ task dispatch from agent chat, task completion notifications, and an Office panel task queue — all backed by the existing TaskPool server infrastructure.

**Architecture:** Client detects `@name` prefix and calls the existing `POST /api/v1/tasks` API with a new `target_agent` field. Server's TaskDispatcher only auto-dispatches tasks with an assigned target. Task completion broadcasts a `TaskCompleted` control event back to the originating session. Office panel adds a collapsible task queue and task-aware agent bubbles.

**Tech Stack:** Rust/Axum (server), Flutter/Dart with Riverpod (client), WebSocket for real-time events

**Spec:** `docs/specs/2026-03-28-phase2-task-dispatch-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `server/crates/core/src/task_pool/types.rs` | Modify | Add `target_agent` field to Task + `source_session_id` |
| `server/crates/core/src/task_pool/pool.rs` | Modify | Skip unassigned tasks in `get_next_executable()` |
| `server/crates/core/src/task_pool/scheduler.rs` | Modify | Broadcast `TaskCompleted` event on task finish |
| `server/crates/core/src/events.rs` | Modify | Add `TaskCompleted` control event variant |
| `server/crates/server/src/api/tasks.rs` | Modify | Accept `target_agent` + `source_session_id` in API, include them in TaskInfo |
| `server/crates/server/src/ws/status.rs` | Modify | Serialize `TaskCompleted` events |
| `client/lib/models/task.dart` | Create | TaskInfo data model |
| `client/lib/services/api_client.dart` | Modify | Add task API methods (create, list, cancel) |
| `client/lib/providers/task_provider.dart` | Create | Global task list provider |
| `client/lib/widgets/agent_picker_menu.dart` | Create | @ autocomplete overlay/bottom sheet |
| `client/lib/widgets/dispatch_dialog.dart` | Create | Task dispatch form dialog |
| `client/lib/widgets/task_queue_panel.dart` | Create | Office bottom collapsible task queue |
| `client/lib/screens/agent_screen.dart` | Modify | @ detection, autocomplete, dispatch, task notifications |
| `client/lib/screens/office_screen.dart` | Modify | Integrate task queue, enhance agent bubbles |
| `client/lib/l10n/strings.dart` | Modify | Add dispatch/task i18n strings |

---

### Task 1: Server — Add target_agent + source_session_id to Task

**Files:**
- Modify: `server/crates/core/src/task_pool/types.rs`

- [ ] **Step 1: Add fields to Task struct**

In `server/crates/core/src/task_pool/types.rs`, add two fields to the `Task` struct after `session_id`:

```rust
    /// Name of the agent this task is assigned to. Empty = unassigned.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target_agent: Option<String>,
    /// Session ID of the agent that dispatched this task (for completion notification).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_session_id: Option<String>,
```

In `Task::new()`, add these fields to the constructor:

```rust
            target_agent: None,
            source_session_id: None,
```

Add builder method after `with_tags`:

```rust
    /// Set the target agent name.
    pub fn with_target_agent(mut self, name: impl Into<String>) -> Self {
        self.target_agent = Some(name.into());
        self
    }

    /// Set the source session ID (who dispatched this task).
    pub fn with_source_session(mut self, session_id: impl Into<String>) -> Self {
        self.source_session_id = Some(session_id.into());
        self
    }
```

- [ ] **Step 2: Verify compilation**

Run: `cd /Users/zhouwei/Projects/ai/relais/server && cargo check -p relais-core 2>&1 | tail -3`

- [ ] **Step 3: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add server/crates/core/src/task_pool/types.rs
git commit -m "feat(server): add target_agent and source_session_id to Task"
```

---

### Task 2: Server — TaskDispatcher: skip unassigned + broadcast TaskCompleted

**Files:**
- Modify: `server/crates/core/src/task_pool/pool.rs`
- Modify: `server/crates/core/src/task_pool/scheduler.rs`
- Modify: `server/crates/core/src/events.rs`
- Modify: `server/crates/server/src/ws/status.rs`

- [ ] **Step 1: Add TaskCompleted to ControlEvent**

In `server/crates/core/src/events.rs`, add variant to `ControlEvent`:

```rust
    TaskCompleted {
        task_id: String,
        source_session_id: String,
        target_name: String,
        success: bool,
        summary: String,
    },
```

- [ ] **Step 2: Skip unassigned tasks in get_next_executable**

Read `server/crates/core/src/task_pool/pool.rs`, find the `get_next_executable()` method. In the filter for executable tasks, add an additional condition: only include tasks where `target_agent` is `Some` (non-empty). Modify the `is_executable` call or add inline filtering:

```rust
    // In get_next_executable(), change the filter to also require a target_agent
    .filter(|t| t.is_executable(&completed_ids) && t.target_agent.is_some())
```

- [ ] **Step 3: Broadcast TaskCompleted on task finish**

Read `server/crates/core/src/task_pool/scheduler.rs`, find the `handle_agent_idle` method. After it updates the task status to Completed/NeedsReview, add a broadcast:

```rust
// After updating task status, broadcast TaskCompleted
if let Some(task) = pool.get(task_id).await {
    if let Some(source_sid) = &task.source_session_id {
        let summary = task.result
            .as_ref()
            .and_then(|r| r.output.clone())
            .unwrap_or_default();
        let summary: String = summary.chars().take(200).collect();

        event_bus.publish_control(ControlEvent::TaskCompleted {
            task_id: task.id.clone(),
            source_session_id: source_sid.clone(),
            target_name: task.target_agent.clone().unwrap_or_default(),
            success: task.status == TaskStatus::Completed,
            summary,
        });
    }
}
```

Note: `handle_agent_idle` needs access to `event_bus`. Check if the dispatcher already has it (it does — `self.event_bus`). The method may be a static method receiving config and pool — if so, add event_bus as a parameter.

Similarly, add broadcast in `handle_agent_crash` for failed tasks.

- [ ] **Step 4: Serialize TaskCompleted in WebSocket**

In `server/crates/server/src/ws/status.rs`, add to `control_event_to_json()`:

```rust
        ControlEvent::TaskCompleted {
            task_id,
            source_session_id,
            target_name,
            success,
            summary,
        } => {
            serde_json::json!({
                "type": "task_completed",
                "task_id": task_id,
                "source_session_id": source_session_id,
                "target_name": target_name,
                "success": success,
                "summary": summary,
            })
        }
```

- [ ] **Step 5: Build**

Run: `cd /Users/zhouwei/Projects/ai/relais/server && cargo build 2>&1 | tail -5`

- [ ] **Step 6: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add server/crates/core/src/task_pool/pool.rs server/crates/core/src/task_pool/scheduler.rs server/crates/core/src/events.rs server/crates/server/src/ws/status.rs
git commit -m "feat(server): skip unassigned tasks in dispatcher, broadcast TaskCompleted"
```

---

### Task 3: Server — Task API: accept target_agent + source_session_id

**Files:**
- Modify: `server/crates/server/src/api/tasks.rs`

- [ ] **Step 1: Update AddTaskRequest**

In `server/crates/server/src/api/tasks.rs`, add fields to `AddTaskRequest`:

```rust
    /// Target agent name for dispatch.
    #[serde(default)]
    pub target_agent: Option<String>,
    /// Session ID of the dispatching agent (for completion callback).
    #[serde(default)]
    pub source_session_id: Option<String>,
```

- [ ] **Step 2: Pass fields through to Task creation**

In the `add_task` handler, after creating the task with `Task::new(...)`, chain the new builder methods:

```rust
    // Find where task is built and add:
    let task = task
        .with_target_agent(req.target_agent.unwrap_or_default())
        .with_source_session(req.source_session_id.unwrap_or_default());
    // Only set if non-empty (adjust with_target_agent to handle empty string → None)
```

Actually, read the handler code to see exactly how the Task is built, then add the fields appropriately. If `target_agent` is an empty string, it should be stored as `None`.

- [ ] **Step 3: Include target_agent in TaskInfo response**

Add `target_agent` and `session_id` to the `TaskInfo` struct:

```rust
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target_agent: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
```

And populate them in the `list_tasks` handler where `TaskInfo` is built from `Task`.

- [ ] **Step 4: Build**

Run: `cd /Users/zhouwei/Projects/ai/relais/server && cargo build 2>&1 | tail -5`

- [ ] **Step 5: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add server/crates/server/src/api/tasks.rs
git commit -m "feat(server): accept target_agent in task creation API, include in list response"
```

---

### Task 4: Client — Task model + API methods + i18n

**Files:**
- Create: `client/lib/models/task.dart`
- Modify: `client/lib/services/api_client.dart`
- Modify: `client/lib/l10n/strings.dart`

- [ ] **Step 1: Create task.dart model**

Create `client/lib/models/task.dart`:

```dart
class TaskInfo {
  final String id;
  final String name;
  final String priority;
  final String status;
  final List<String> dependsOn;
  final String createdAt;
  final String? startedAt;
  final String? completedAt;
  final String? targetAgent;
  final String? sessionId;

  const TaskInfo({
    required this.id,
    required this.name,
    required this.priority,
    required this.status,
    this.dependsOn = const [],
    required this.createdAt,
    this.startedAt,
    this.completedAt,
    this.targetAgent,
    this.sessionId,
  });

  factory TaskInfo.fromJson(Map<String, dynamic> json) => TaskInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        priority: json['priority'] as String? ?? 'P1',
        status: json['status'] as String,
        dependsOn: (json['depends_on'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        createdAt: json['created_at'] as String,
        startedAt: json['started_at'] as String?,
        completedAt: json['completed_at'] as String?,
        targetAgent: json['target_agent'] as String?,
        sessionId: json['session_id'] as String?,
      );

  bool get isRunning => status == 'running';
  bool get isQueued => status == 'queued';
  bool get isUnassigned => targetAgent == null || targetAgent!.isEmpty;
}
```

- [ ] **Step 2: Add task API methods to ApiClient**

In `client/lib/services/api_client.dart`, add import:

```dart
import '../models/task.dart';
```

Add methods:

```dart
  Future<List<TaskInfo>> getTasks() async {
    final resp = await _dio.get('/api/v1/tasks');
    final list = resp.data as List;
    return list
        .map((e) => TaskInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> createTask({
    required String title,
    String prompt = '',
    String priority = 'p1',
    String? targetAgent,
    String? sourceSessionId,
    String? cwd,
  }) async {
    final resp = await _dio.post('/api/v1/tasks', data: {
      'title': title,
      if (prompt.isNotEmpty) 'prompt': prompt,
      'priority': priority,
      if (targetAgent != null) 'target_agent': targetAgent,
      if (sourceSessionId != null) 'source_session_id': sourceSessionId,
      if (cwd != null) 'cwd': cwd,
    });
    return resp.data as Map<String, dynamic>;
  }

  Future<void> cancelTask(String id) async {
    await _dio.delete('/api/v1/tasks/$id');
  }
```

- [ ] **Step 3: Add i18n strings**

In `client/lib/l10n/strings.dart`, add before `_t`:

```dart
  static String get dispatchTo => _t('派发给', 'Dispatch to');
  static String dispatched(String name, String task) =>
      _t('已派发给 $name：$task', 'Dispatched to $name: $task');
  static String get taskQueue => _t('任务队列', 'Task Queue');
  static String get unassigned => _t('待分配', 'Unassigned');
  static String get newTask => _t('新建任务', 'New Task');
  static String get taskTitle => _t('任务标题', 'Task title');
  static String get taskDescription => _t('任务描述', 'Task description');
  static String get priority => _t('优先级', 'Priority');
  static String get dispatch => _t('派发', 'Dispatch');
  static String get selectAgent => _t('选择 Agent', 'Select Agent');
  static String taskCompleted(String name, String task) =>
      _t('$name 完成了任务：$task', '$name completed: $task');
  static String taskFailed(String name, String task) =>
      _t('$name 任务失败：$task', '$name failed: $task');
  static String get agentNotFound => _t('目标 Agent 不存在', 'Target agent not found');
```

- [ ] **Step 4: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add client/lib/models/task.dart client/lib/services/api_client.dart client/lib/l10n/strings.dart
git commit -m "feat(client): add Task model, API methods, and dispatch i18n strings"
```

---

### Task 5: Client — TaskProvider

**Files:**
- Create: `client/lib/providers/task_provider.dart`

- [ ] **Step 1: Create provider**

Create `client/lib/providers/task_provider.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task.dart';
import '../providers/server_provider.dart';
import '../services/api_client.dart';

class TaskNotifier extends StateNotifier<List<TaskInfo>> {
  final ApiClient? _api;
  Timer? _refreshTimer;

  TaskNotifier({ApiClient? api})
      : _api = api,
        super([]) {
    if (_api != null) _init();
  }

  void _init() {
    refresh();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => refresh(),
    );
  }

  Future<void> refresh() async {
    if (_api == null) return;
    try {
      final tasks = await _api.getTasks();
      state = tasks;
    } catch (_) {}
  }

  Future<String?> createTask({
    required String title,
    String prompt = '',
    String priority = 'p1',
    String? targetAgent,
    String? sourceSessionId,
    String? cwd,
  }) async {
    if (_api == null) return null;
    try {
      final resp = await _api.createTask(
        title: title,
        prompt: prompt,
        priority: priority,
        targetAgent: targetAgent,
        sourceSessionId: sourceSessionId,
        cwd: cwd,
      );
      await refresh();
      return resp['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> cancelTask(String id) async {
    if (_api == null) return;
    try {
      await _api.cancelTask(id);
      await refresh();
    } catch (_) {}
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

final taskProvider =
    StateNotifierProvider<TaskNotifier, List<TaskInfo>>((ref) {
  final server = ref.watch(serverProvider).server;
  if (server == null) return TaskNotifier();
  return TaskNotifier(
    api: ApiClient(baseUrl: server.url, token: server.token),
  );
});
```

- [ ] **Step 2: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add client/lib/providers/task_provider.dart
git commit -m "feat(client): add TaskProvider with periodic refresh"
```

---

### Task 6: Client — @ Autocomplete Menu + Dispatch Dialog

**Files:**
- Create: `client/lib/widgets/agent_picker_menu.dart`
- Create: `client/lib/widgets/dispatch_dialog.dart`

- [ ] **Step 1: Create agent_picker_menu.dart**

Create `client/lib/widgets/agent_picker_menu.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import '../models/agent_status.dart';
import '../widgets/office_painter.dart' show providerColor;

bool get _isMobilePlatform {
  final p = defaultTargetPlatform;
  return p == TargetPlatform.iOS || p == TargetPlatform.android;
}

class AgentPickerController {
  OverlayEntry? _overlayEntry;

  void show({
    required BuildContext context,
    required LayerLink layerLink,
    required List<AgentStatusInfo> agents,
    required ValueChanged<AgentStatusInfo> onSelect,
    required VoidCallback onDismiss,
  }) {
    if (_isMobilePlatform) {
      _showBottomSheet(context, agents, onSelect, onDismiss);
      return;
    }
    _removeOverlay();
    _overlayEntry = OverlayEntry(
      builder: (_) => _DesktopAgentPicker(
        layerLink: layerLink,
        agents: agents,
        onSelect: (agent) {
          _removeOverlay();
          onSelect(agent);
        },
        onDismiss: () {
          _removeOverlay();
          onDismiss();
        },
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  bool get isVisible => _overlayEntry != null;
  void dismiss() => _removeOverlay();

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showBottomSheet(
    BuildContext context,
    List<AgentStatusInfo> agents,
    ValueChanged<AgentStatusInfo> onSelect,
    VoidCallback onDismiss,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 32, height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            ...agents.map((agent) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: providerColor(agent.provider),
                    radius: 16,
                    child: Text(agent.name[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                  title: Text(agent.name),
                  subtitle: Text('${agent.provider} · ${agent.status}'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onSelect(agent);
                  },
                )),
          ],
        ),
      ),
    ).whenComplete(onDismiss);
  }
}

class _DesktopAgentPicker extends StatelessWidget {
  final LayerLink layerLink;
  final List<AgentStatusInfo> agents;
  final ValueChanged<AgentStatusInfo> onSelect;
  final VoidCallback onDismiss;

  const _DesktopAgentPicker({
    required this.layerLink,
    required this.agents,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          constraints: const BoxConstraints(maxHeight: 240, maxWidth: 300),
          child: agents.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No agents available'),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: agents.length,
                  itemBuilder: (context, index) {
                    final agent = agents[index];
                    return InkWell(
                      onTap: () => onSelect(agent),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: providerColor(agent.provider),
                              radius: 14,
                              child: Text(
                                agent.name[0].toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(agent.name,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(fontWeight: FontWeight.w600)),
                                  Text('${agent.provider} · ${agent.status}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.outline)),
                                ],
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
```

- [ ] **Step 2: Create dispatch_dialog.dart**

Create `client/lib/widgets/dispatch_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import '../models/agent_status.dart';
import '../widgets/office_painter.dart' show providerColor;
import '../l10n/strings.dart';

class DispatchDialog extends StatefulWidget {
  final List<AgentStatusInfo> agents;
  final void Function(String targetAgent, String title, String prompt, String priority) onDispatch;

  const DispatchDialog({
    super.key,
    required this.agents,
    required this.onDispatch,
  });

  @override
  State<DispatchDialog> createState() => _DispatchDialogState();
}

class _DispatchDialogState extends State<DispatchDialog> {
  AgentStatusInfo? _selectedAgent;
  final _titleController = TextEditingController();
  final _promptController = TextEditingController();
  String _priority = 'p1';

  @override
  void dispose() {
    _titleController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(S.newTask),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Agent selection
            Text(S.selectAgent, style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: widget.agents.map((agent) {
                final selected = _selectedAgent?.sessionId == agent.sessionId;
                return ChoiceChip(
                  avatar: CircleAvatar(
                    backgroundColor: providerColor(agent.provider),
                    radius: 10,
                    child: Text(agent.name[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 9)),
                  ),
                  label: Text(agent.name),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedAgent = agent),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            // Title
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: S.taskTitle,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            // Description
            TextField(
              controller: _promptController,
              decoration: InputDecoration(
                labelText: S.taskDescription,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            // Priority
            Row(
              children: [
                Text(S.priority, style: theme.textTheme.labelMedium),
                const SizedBox(width: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'p0', label: Text('P0')),
                    ButtonSegment(value: 'p1', label: Text('P1')),
                    ButtonSegment(value: 'p2', label: Text('P2')),
                  ],
                  selected: {_priority},
                  onSelectionChanged: (v) =>
                      setState(() => _priority = v.first),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.cancel),
        ),
        FilledButton(
          onPressed: _selectedAgent == null || _titleController.text.trim().isEmpty
              ? null
              : () {
                  widget.onDispatch(
                    _selectedAgent!.name,
                    _titleController.text.trim(),
                    _promptController.text.trim(),
                    _priority,
                  );
                  Navigator.of(context).pop();
                },
          child: Text(S.dispatch),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add client/lib/widgets/agent_picker_menu.dart client/lib/widgets/dispatch_dialog.dart
git commit -m "feat(client): add AgentPickerMenu and DispatchDialog widgets"
```

---

### Task 7: Client — Agent Screen: @ dispatch + task notifications

**Files:**
- Modify: `client/lib/screens/agent_screen.dart`

- [ ] **Step 1: Add imports and state**

Read `client/lib/screens/agent_screen.dart` first. Add imports:

```dart
import '../providers/agent_status_provider.dart';
import '../providers/task_provider.dart';
import '../widgets/agent_picker_menu.dart';
import '../widgets/dispatch_dialog.dart';
import '../models/agent_status.dart';
```

Add fields to `_AgentScreenState`:

```dart
  final _agentPickerController = AgentPickerController();
  bool _showingAgentPicker = false;
```

- [ ] **Step 2: Add @ detection in _onInputChanged**

Modify the existing `_onInputChanged` method. After the slash command detection block, add @ detection:

```dart
    // @ agent picker
    if (text.startsWith('@') && !text.contains(' ')) {
      final agents = ref.read(agentStatusProvider);
      final agentList = agents.values
          .where((a) => a.sessionId != widget.sessionId) // exclude self
          .toList();
      if (agentList.isNotEmpty) {
        if (!_showingAgentPicker) {
          _showingAgentPicker = true;
          _agentPickerController.show(
            context: context,
            layerLink: _layerLink,
            agents: agentList,
            onSelect: _onAgentSelected,
            onDismiss: () => _showingAgentPicker = false,
          );
        }
      }
    } else if (_showingAgentPicker) {
      _agentPickerController.dismiss();
      _showingAgentPicker = false;
    }
```

- [ ] **Step 3: Add agent selection and dispatch handlers**

Add methods:

```dart
  void _onAgentSelected(AgentStatusInfo agent) {
    _inputController.text = '@${agent.name} ';
    _inputController.selection = TextSelection.collapsed(
      offset: _inputController.text.length,
    );
    _showingAgentPicker = false;
    _inputFocusNode.requestFocus();
  }

  Future<void> _dispatchTask(String text) async {
    // Parse @name description
    final spaceIndex = text.indexOf(' ');
    if (spaceIndex < 0) return;
    final targetName = text.substring(1, spaceIndex);
    final description = text.substring(spaceIndex + 1).trim();
    if (description.isEmpty) return;

    // Validate agent exists
    final agents = ref.read(agentStatusProvider);
    final targetExists = agents.values.any((a) => a.name == targetName);
    if (!targetExists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.agentNotFound)),
        );
      }
      return;
    }

    // Create task
    final taskNotifier = ref.read(taskProvider.notifier);
    await taskNotifier.createTask(
      title: description.length > 50
          ? '${description.substring(0, 50)}...'
          : description,
      prompt: description,
      targetAgent: targetName,
      sourceSessionId: widget.sessionId,
    );

    // Insert local system message
    _session!.messages.add(AgentMessage(
      id: 'dispatch-${DateTime.now().millisecondsSinceEpoch}',
      type: AgentMessageType.progress,
      content: S.dispatched(targetName, description),
      timestamp: DateTime.now(),
    ));
    setState(() {});
  }

  void _showDispatchDialog() {
    final agents = ref.read(agentStatusProvider);
    final agentList = agents.values
        .where((a) => a.sessionId != widget.sessionId)
        .toList();
    showDialog(
      context: context,
      builder: (_) => DispatchDialog(
        agents: agentList,
        onDispatch: (targetAgent, title, prompt, priority) async {
          final taskNotifier = ref.read(taskProvider.notifier);
          await taskNotifier.createTask(
            title: title,
            prompt: prompt.isEmpty ? title : prompt,
            priority: priority,
            targetAgent: targetAgent,
            sourceSessionId: widget.sessionId,
          );
          _session!.messages.add(AgentMessage(
            id: 'dispatch-${DateTime.now().millisecondsSinceEpoch}',
            type: AgentMessageType.progress,
            content: S.dispatched(targetAgent, title),
            timestamp: DateTime.now(),
          ));
          if (mounted) setState(() {});
        },
      ),
    );
  }
```

- [ ] **Step 4: Modify _sendMessage to detect @**

In `_sendMessage()`, add @ detection before sending:

```dart
  void _sendMessage() {
    _dismissMenu();
    final text = _inputController.text.trim();
    if (text.isEmpty || _session == null) return;

    // @ dispatch — don't send to current agent
    if (text.startsWith('@') && text.contains(' ')) {
      _dispatchTask(text);
      _inputController.value = TextEditingValue.empty;
      return;
    }

    // ... rest of existing code (cancel voice, send to agent, clear input)
```

- [ ] **Step 5: Add @ button to input area**

In the `build()` method, add an @ IconButton before the input field. Find the `Row` containing the TextField and add:

```dart
  IconButton(
    onPressed: _showDispatchDialog,
    icon: const Text('@', style: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
    )),
    tooltip: S.dispatchTo,
  ),
```

- [ ] **Step 6: Clean up in dispose**

Add to `dispose()`:

```dart
    _agentPickerController.dismiss();
```

- [ ] **Step 7: Verify**

Run: `cd /Users/zhouwei/Projects/ai/relais/client && flutter analyze lib/screens/agent_screen.dart 2>&1 | tail -5`

- [ ] **Step 8: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add client/lib/screens/agent_screen.dart
git commit -m "feat(client): add @ dispatch detection, autocomplete, and dispatch dialog in agent screen"
```

---

### Task 8: Client — Task Queue Panel for Office

**Files:**
- Create: `client/lib/widgets/task_queue_panel.dart`
- Modify: `client/lib/screens/office_screen.dart`

- [ ] **Step 1: Create task_queue_panel.dart**

Create `client/lib/widgets/task_queue_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/task.dart';
import '../l10n/strings.dart';

class TaskQueuePanel extends StatefulWidget {
  final List<TaskInfo> tasks;
  final VoidCallback onNewTask;

  const TaskQueuePanel({
    super.key,
    required this.tasks,
    required this.onNewTask,
  });

  @override
  State<TaskQueuePanel> createState() => _TaskQueuePanelState();
}

class _TaskQueuePanelState extends State<TaskQueuePanel> {
  bool _expanded = false;

  List<TaskInfo> get _activeTasks =>
      widget.tasks.where((t) => !_isTerminal(t.status)).toList();

  bool _isTerminal(String status) =>
      status == 'completed' || status == 'failed' || status == 'cancelled';

  Color _priorityColor(String priority) {
    switch (priority.toUpperCase()) {
      case 'P0':
        return Colors.red;
      case 'P1':
        return Colors.orange;
      case 'P2':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Widget _statusIcon(String status) {
    switch (status) {
      case 'running':
        return const Text('🟢', style: TextStyle(fontSize: 12));
      case 'queued':
        return const Text('🟡', style: TextStyle(fontSize: 12));
      case 'needs_review':
        return const Text('🔵', style: TextStyle(fontSize: 12));
      default:
        return const Text('⚪', style: TextStyle(fontSize: 12));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _activeTasks;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header bar
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Text('📋 ${S.taskQueue} (${active.length})',
                      style: theme.textTheme.titleSmall),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: widget.onNewTask,
                    tooltip: S.newTask,
                    visualDensity: VisualDensity.compact,
                  ),
                  Icon(
                    _expanded ? Icons.expand_more : Icons.expand_less,
                    size: 20,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
          // Expanded task list
          if (_expanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: active.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(S.noAgentsRunning,
                          style: theme.textTheme.bodySmall),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: active.length,
                      itemBuilder: (context, index) {
                        final task = active[index];
                        return InkWell(
                          onTap: task.isRunning && task.sessionId != null
                              ? () => context
                                  .push('/agent/${task.sessionId}')
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            child: Row(
                              children: [
                                // Priority chip
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _priorityColor(task.priority)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(task.priority.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: _priorityColor(task.priority),
                                      )),
                                ),
                                const SizedBox(width: 8),
                                // Title
                                Expanded(
                                  child: Text(task.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall),
                                ),
                                const SizedBox(width: 8),
                                // Target agent
                                Text(
                                  task.isUnassigned
                                      ? S.unassigned
                                      : '→ ${task.targetAgent}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: task.isUnassigned
                                        ? theme.colorScheme.outline
                                        : theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Status
                                _statusIcon(task.status),
                              ],
                            ),
                          ),
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

- [ ] **Step 2: Integrate into OfficeScreen**

Read `client/lib/screens/office_screen.dart`. Modify it to:

1. Add imports:
```dart
import '../providers/task_provider.dart';
import '../providers/agent_status_provider.dart';
import '../widgets/task_queue_panel.dart';
import '../widgets/dispatch_dialog.dart';
import '../models/agent_status.dart';
```

2. Watch `taskProvider` alongside `agentStatusProvider`:
```dart
    final tasks = ref.watch(taskProvider);
```

3. Wrap the body in a `Column` with the canvas and task queue panel:
```dart
      body: Column(
        children: [
          Expanded(
            child: agentList.isEmpty
                ? /* existing empty state */
                : /* existing AnimatedBuilder with canvas */,
          ),
          TaskQueuePanel(
            tasks: tasks,
            onNewTask: () => _showDispatchDialog(context, ref),
          ),
        ],
      ),
```

4. Add `_showDispatchDialog` method:
```dart
  void _showDispatchDialog(BuildContext context, WidgetRef ref) {
    final agents = ref.read(agentStatusProvider);
    showDialog(
      context: context,
      builder: (_) => DispatchDialog(
        agents: agents.values.toList(),
        onDispatch: (targetAgent, title, prompt, priority) {
          ref.read(taskProvider.notifier).createTask(
            title: title,
            prompt: prompt.isEmpty ? title : prompt,
            priority: priority,
            targetAgent: targetAgent,
          );
        },
      ),
    );
  }
```

5. Enhance agent bubbles: in the `AgentPainter` usage, check if the agent has a linked running task. If so, override the activity text with the task title. Merge task data by matching `task.sessionId == agent.sessionId`:

```dart
// Before building AgentPainter, check for linked task
final linkedTask = tasks
    .where((t) => t.isRunning && t.sessionId == agent.sessionId)
    .firstOrNull;
final displayAgent = linkedTask != null
    ? AgentStatusInfo(
        sessionId: agent.sessionId,
        name: agent.name,
        provider: agent.provider,
        status: agent.status,
        activity: '📋 ${linkedTask.name}',
        costUsd: agent.costUsd,
      )
    : agent;
```

- [ ] **Step 3: Verify**

Run: `cd /Users/zhouwei/Projects/ai/relais/client && flutter analyze 2>&1 | tail -5`

- [ ] **Step 4: Commit**

```bash
cd /Users/zhouwei/Projects/ai/relais
git add client/lib/widgets/task_queue_panel.dart client/lib/screens/office_screen.dart
git commit -m "feat(client): add TaskQueuePanel to Office, enhance agent bubbles with task titles"
```

---

### Task 9: Integration build + verification

- [ ] **Step 1: Build server**

Run: `cd /Users/zhouwei/Projects/ai/relais/server && cargo build 2>&1 | tail -5`

- [ ] **Step 2: Analyze client**

Run: `cd /Users/zhouwei/Projects/ai/relais/client && flutter analyze 2>&1 | tail -10`

- [ ] **Step 3: Manual E2E test**

1. Start server
2. Connect client
3. Create 2 agent sessions (e.g., "main" and "helper")
4. In "main" agent chat, type `@` → verify agent picker shows "helper"
5. Select "helper", type a task: `@helper 帮我跑测试`
6. Verify: system message appears in chat, task appears in Office task queue
7. Open Office → verify task queue panel shows the task assigned to "helper"
8. Verify "helper" agent bubble shows task title
9. When task completes, verify notification appears in "main" chat
