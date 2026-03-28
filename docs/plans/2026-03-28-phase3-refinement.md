# Phase 3: Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor task/agent model to reuse existing agents, add session persistence via CLI `--resume`, and improve the office area with scrolling, provider grouping, and distinct agent visuals.

**Architecture:** Server-side changes flow bottom-up: persistence layer first (session ID storage + resume), then dispatch refactor (reuse agents), then config (provider registry). Client changes follow: creation dialog, dispatch dialog, office canvas. Each task is independently committable.

**Tech Stack:** Rust (server: axum, tokio, serde), Flutter/Dart (client: riverpod, CustomPaint)

---

## File Map

### Server — Create
- (none — all modifications to existing files)

### Server — Modify
| File | Changes |
|------|---------|
| `server/crates/core/src/session/types.rs` | Add `acp_session_id` field to `SessionMeta` |
| `server/crates/core/src/agent/acp_backend.rs` | Add `resume_session_id` param to `start()` |
| `server/crates/core/src/agent/manager.rs` | Add `create_agent_with_resume()`, persist `acp_session_id` on TurnComplete |
| `server/crates/server/src/ws/agent.rs` | Pass `acp_session_id` in resume path |
| `server/crates/core/src/task_pool/types.rs` | Add `provider` field to `Task` |
| `server/crates/server/src/api/tasks.rs` | Add `provider` field to `AddTaskRequest` |
| `server/crates/core/src/task_pool/scheduler.rs` | Refactor `dispatch_tick` for two-path dispatch, add pending-tasks map |
| `server/crates/core/src/config.rs` | Add `ProviderDef` struct, `providers` list to `AgentConfig` |
| `server/crates/server/src/api/sessions.rs` | Add `GET /api/v1/providers` endpoint |
| `server/crates/server/src/router.rs` | Add providers route |

### Client — Modify
| File | Changes |
|------|---------|
| `client/lib/services/api_client.dart` | Add `getProviders()`, add `provider` to `createTask()` |
| `client/lib/models/task.dart` | Add `provider` field |
| `client/lib/screens/home_screen.dart` | Replace instant-create with dialog, add name input |
| `client/lib/widgets/dispatch_dialog.dart` | Add grouped agents + "new agent" option |
| `client/lib/providers/settings_provider.dart` | Add provider filter to builtin slash commands |
| `client/lib/widgets/office_painter.dart` | Provider grouping layout, head shapes per provider, remove desk |
| `client/lib/screens/office_screen.dart` | Wrap in InteractiveViewer |

---

## Task 1: Add `acp_session_id` to SessionMeta

**Files:**
- Modify: `server/crates/core/src/session/types.rs:7-24`

- [ ] **Step 1: Add field to SessionMeta**

In `server/crates/core/src/session/types.rs`, add `acp_session_id` after the `tags` field:

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionMeta {
    pub id: SessionId,
    pub name: String,
    pub session_type: SessionType,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub agent: Option<AgentInfo>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub shell: Option<String>,
    pub cwd: String,
    pub created_at: DateTime<Utc>,
    pub last_active: DateTime<Utc>,
    pub last_seq: u64,
    pub status: SessionStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent_id: Option<SessionId>,
    #[serde(default)]
    pub tags: Vec<String>,
    /// CLI session ID for --resume support (e.g. Claude Code session ID).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub acp_session_id: Option<String>,
}
```

- [ ] **Step 2: Update all SessionMeta construction sites**

Grep for `SessionMeta {` in the codebase. Each construction site needs `acp_session_id: None`. Currently these are in:
- `server/crates/core/src/agent/manager.rs` (create_agent)
- `server/crates/core/src/pty/manager.rs` (create_session)

Add `acp_session_id: None,` to both.

- [ ] **Step 3: Verify build**

Run: `cd server && cargo check`
Expected: Clean compilation (the field has `#[serde(default)]` so existing meta.json files deserialize correctly)

- [ ] **Step 4: Commit**

```bash
git add server/crates/core/src/session/types.rs server/crates/core/src/agent/manager.rs server/crates/core/src/pty/manager.rs
git commit -m "feat(core): add acp_session_id to SessionMeta for resume support"
```

---

## Task 2: Wire resume_session_id through AcpBackend

**Files:**
- Modify: `server/crates/core/src/agent/acp_backend.rs:66`
- Modify: `server/crates/core/src/agent/manager.rs:83-90`

- [ ] **Step 1: Change AcpBackend::start() signature**

In `acp_backend.rs`, change the `start` method signature from:

```rust
pub async fn start(&mut self, cwd: &Path, system_prompt: Option<&str>) -> Result<(), String>
```

to:

```rust
pub async fn start(&mut self, cwd: &Path, resume_session_id: Option<&str>) -> Result<(), String>
```

Update the internal spawn call to pass `resume_session_id` instead of `system_prompt` to `ClaudeSdk::spawn()`. The `ClaudeSdk::spawn()` already accepts `resume_session_id: Option<&str>` as its third parameter.

- [ ] **Step 2: Add create_agent_with_resume to AgentManager**

In `manager.rs`, add a new method that accepts an optional resume ID:

```rust
/// Create and start a new agent session, optionally resuming a previous CLI session.
pub async fn create_agent_with_resume(
    &self,
    session_id: SessionId,
    name: &str,
    provider: &str,
    _model: &str,
    cwd: PathBuf,
    resume_session_id: Option<&str>,
) -> Result<(), String> {
    // Same body as create_agent but passes resume_session_id to backend.start()
}
```

Refactor `create_agent` to call `create_agent_with_resume(..., None)`.

- [ ] **Step 3: Persist acp_session_id on TurnComplete**

In the event router (manager.rs `start_event_router`), after the `AgentEvent::TurnComplete` match arm, add:

```rust
AgentEvent::TurnComplete { session_id: cli_sid, cost_usd } => {
    if let Some(ref s) = cli_sid {
        if let Ok(mut meta) = session_store.get_meta(&sid) {
            if meta.acp_session_id.as_deref() != Some(s.as_str()) {
                meta.acp_session_id = Some(s.clone());
                let _ = session_store.update_meta(&sid, &meta);
            }
        }
    }
    (AgentActivity::Idle, String::new(), *cost_usd)
}
```

This updates `meta.json` with the CLI session ID only when it changes.

- [ ] **Step 4: Verify build and tests**

Run: `cd server && cargo test -p relais-core`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add server/crates/core/src/agent/acp_backend.rs server/crates/core/src/agent/manager.rs
git commit -m "feat(core): wire resume_session_id through AcpBackend and persist on TurnComplete"
```

---

## Task 3: Wire resume in WebSocket handler

**Files:**
- Modify: `server/crates/server/src/ws/agent.rs:62-116`

- [ ] **Step 1: Pass acp_session_id in resume path**

In `ws_agent`, the current resume block calls `agent_manager.create_agent()`. Change it to:

```rust
if can_resume {
    if let Ok(meta) = state.core.session_store.get_meta(&session_id) {
        let provider = meta.agent.as_ref().map(|a| a.provider.as_str()).unwrap_or("claude-code");
        let model = meta.agent.as_ref().map(|a| a.model.as_str()).unwrap_or("");
        let cwd = std::path::PathBuf::from(&meta.cwd);
        let resume_id = meta.acp_session_id.as_deref();

        info!(session_id = %session_id, name = %meta.name, resume = resume_id.is_some(), "resuming suspended agent session");
        if let Err(e) = state.core.agent_manager
            .create_agent_with_resume(session_id.clone(), &meta.name, provider, model, cwd, resume_id)
            .await
        {
            // ... existing error handling ...
        }
        // ... existing meta status update ...
    }
}
```

- [ ] **Step 2: Verify build**

Run: `cd server && cargo check`
Expected: Clean compilation

- [ ] **Step 3: Commit**

```bash
git add server/crates/server/src/ws/agent.rs
git commit -m "feat(server): pass acp_session_id when resuming suspended agent sessions"
```

---

## Task 4: Add provider field to Task and API

**Files:**
- Modify: `server/crates/core/src/task_pool/types.rs:121-165`
- Modify: `server/crates/server/src/api/tasks.rs:17-38`
- Modify: `client/lib/models/task.dart`
- Modify: `client/lib/services/api_client.dart:78-95`
- Modify: `client/lib/providers/task_provider.dart:71-95`

- [ ] **Step 1: Add provider to Task struct (server)**

In `types.rs`, add after `target_agent`:

```rust
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub provider: Option<String>,
```

Also add to `Task::new()` default initialization: `provider: None,`

Add builder method:

```rust
pub fn with_provider(mut self, provider: impl Into<String>) -> Self {
    let p = provider.into();
    self.provider = if p.is_empty() { None } else { Some(p) };
    self
}
```

- [ ] **Step 2: Add provider to AddTaskRequest (server)**

In `tasks.rs` `AddTaskRequest`:

```rust
#[serde(default)]
pub provider: Option<String>,
```

In `add_task` handler, after the `target_agent` block:

```rust
if let Some(provider) = body.provider {
    task = task.with_provider(provider);
}
```

- [ ] **Step 3: Add provider to TaskInfo (client)**

In `client/lib/models/task.dart`:

```dart
class TaskInfo {
  // ... existing fields ...
  final String? provider;

  // Add to constructor, fromJson
}
```

- [ ] **Step 4: Add provider param to createTask (client)**

In `api_client.dart` `createTask`, add `String? provider` parameter and include in the POST data:

```dart
if (provider != null) 'provider': provider,
```

Do the same in `task_provider.dart` `createTask`.

- [ ] **Step 5: Verify build**

Run: `cd server && cargo check` and `cd client && flutter analyze`
Expected: Both clean

- [ ] **Step 6: Commit**

```bash
git add server/crates/core/src/task_pool/types.rs server/crates/server/src/api/tasks.rs \
       client/lib/models/task.dart client/lib/services/api_client.dart client/lib/providers/task_provider.dart
git commit -m "feat: add provider field to Task model and API"
```

---

## Task 5: Refactor dispatch_tick for two-path dispatch

**Files:**
- Modify: `server/crates/core/src/task_pool/scheduler.rs:166-316`
- Modify: `server/crates/core/src/task_pool/pool.rs:293-322`

- [ ] **Step 1: Update get_next_executable to include provider-only tasks**

In `pool.rs`, change the filter to also accept tasks with `provider.is_some()`:

```rust
let mut candidates: Vec<&Task> = tasks
    .iter()
    .filter(|t| t.is_executable(&completed_ids) && (t.target_agent.is_some() || t.provider.is_some()))
    .collect();
```

- [ ] **Step 2: Add pending_tasks map to dispatcher**

Add to the `dispatch_tick` context (or make it a static within the function scope). Since `dispatch_tick` is a static async fn, use a shared state. Add to `TaskDispatcher`:

```rust
pub struct TaskDispatcher {
    // ... existing fields ...
    /// Maps agent session IDs to their currently-processing task ID.
    pending_tasks: Arc<tokio::sync::RwLock<std::collections::HashMap<String, String>>>,
}
```

Initialize in `new()`: `pending_tasks: Arc::new(tokio::sync::RwLock::new(std::collections::HashMap::new()))`.

- [ ] **Step 3: Refactor dispatch_tick with two paths**

Replace the agent creation block (lines ~200-315) with:

```rust
// Path A: target_agent specified — send to existing agent
if let Some(ref target_name) = task.target_agent {
    // Find running agent by name
    let agent_session = agent_manager.find_agent_by_name(target_name);
    if let Some(agent_sid) = agent_session {
        // Mark as running
        if let Err(e) = pool.update_status(&task.id, TaskStatus::Running).await {
            error!(id = %task.id, error = %e, "failed to mark task as running");
            continue;
        }
        if let Err(e) = pool.set_session_id(&task.id, agent_sid.clone()).await {
            error!(id = %task.id, error = %e, "failed to set session_id");
        }
        // Track this task for completion detection
        pending_tasks.write().await.insert(agent_sid.clone(), task.id.clone());
        // Send prompt to existing agent
        let prompt = build_task_prompt(&task);
        if let Err(e) = agent_manager.send_message(&agent_sid, prompt).await {
            error!(id = %task.id, error = %e, "failed to send task to agent");
            let _ = pool.update_status(&task.id, TaskStatus::Failed).await;
            pending_tasks.write().await.remove(&agent_sid);
        } else {
            info!(id = %task.id, agent = %agent_sid, "task dispatched to existing agent");
        }
        continue;
    }
    // Agent not found — fall through to try provider path
}

// Path B: create new agent (by provider or default)
let provider = task.provider.as_deref()
    .or(Some("claude-code"))
    .unwrap();
// ... existing create_agent + send_message logic, using provider ...
```

- [ ] **Step 4: Add find_agent_by_name to AgentManager**

In `manager.rs`:

```rust
/// Find a running agent's session ID by name.
pub fn find_agent_by_name(&self, name: &str) -> Option<String> {
    self.agents.iter()
        .find(|entry| entry.value().name == name)
        .map(|entry| entry.key().clone())
}
```

- [ ] **Step 5: Handle task completion for reused agents**

In `handle_control_event`, modify the `AgentStatusChanged(Idle)` handler to also check `pending_tasks`:

```rust
// Check if this session has a pending task (reused agent path)
if let Some(task_id) = pending_tasks.write().await.remove(session_id) {
    // Same completion logic as task-* sessions
    Self::complete_pending_task(config, pool, event_bus, &task_id, session_id).await;
    return;
}
// Existing task-* prefix check continues below
```

- [ ] **Step 6: Verify build and tests**

Run: `cd server && cargo test -p relais-core -- test_priority test_fifo test_dependency`
Expected: All pass

- [ ] **Step 7: Commit**

```bash
git add server/crates/core/src/task_pool/scheduler.rs server/crates/core/src/task_pool/pool.rs \
       server/crates/core/src/agent/manager.rs
git commit -m "feat(core): refactor task dispatch to reuse existing agents or create by provider"
```

---

## Task 6: Provider config and API endpoint

**Files:**
- Modify: `server/crates/core/src/config.rs`
- Modify: `server/crates/server/src/api/sessions.rs`
- Modify: `server/crates/server/src/router.rs`
- Modify: `client/lib/services/api_client.dart`

- [ ] **Step 1: Add ProviderDef to config**

In `config.rs`, add:

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderDef {
    pub id: String,
    pub name: String,
    pub command: String,
}
```

Add to `AgentConfig`:

```rust
pub struct AgentConfig {
    // ... existing fields ...
    #[serde(default = "default_providers")]
    pub providers: Vec<ProviderDef>,
}

fn default_providers() -> Vec<ProviderDef> {
    vec![
        ProviderDef { id: "claude-code".into(), name: "Claude Code".into(), command: "claude".into() },
        ProviderDef { id: "codex".into(), name: "Codex CLI".into(), command: "codex".into() },
        ProviderDef { id: "gemini".into(), name: "Gemini CLI".into(), command: "gemini".into() },
    ]
}
```

Remove `default_provider` field from `AgentConfig`.

- [ ] **Step 2: Add GET /api/v1/providers endpoint**

In `sessions.rs`:

```rust
pub async fn list_providers(State(state): State<AppState>) -> impl IntoResponse {
    let providers: Vec<serde_json::Value> = state.core.config.agent.providers.iter()
        .map(|p| serde_json::json!({
            "id": p.id,
            "name": p.name,
        }))
        .collect();
    Json(providers)
}
```

In `router.rs`, add route: `.route("/providers", get(sessions::list_providers))`

- [ ] **Step 3: Add getProviders to client ApiClient**

In `api_client.dart`:

```dart
Future<List<Map<String, dynamic>>> getProviders() async {
    final resp = await _dio.get('/api/v1/providers');
    final list = resp.data as List;
    return list.cast<Map<String, dynamic>>();
}
```

- [ ] **Step 4: Verify build**

Run: `cd server && cargo check` and `cd client && flutter analyze`

- [ ] **Step 5: Commit**

```bash
git add server/crates/core/src/config.rs server/crates/server/src/api/sessions.rs \
       server/crates/server/src/router.rs client/lib/services/api_client.dart
git commit -m "feat: add provider registry config and API endpoint"
```

---

## Task 7: Client — Agent creation dialog with name + type

**Files:**
- Modify: `client/lib/screens/home_screen.dart:112-147`

- [ ] **Step 1: Replace _showCreateDialog**

Replace the `_showCreateDialog` method. When user selects "New Agent", show a dialog with name input and provider selection instead of instantly creating:

```dart
void _showCreateDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.terminal),
              title: Text(S.newTerminal),
              onTap: () {
                Navigator.pop(context);
                _showNameDialog(SessionKind.terminal);
              },
            ),
            ListTile(
              leading: const Icon(Icons.smart_toy),
              title: Text(S.newAgent),
              onTap: () {
                Navigator.pop(context);
                _showAgentCreateDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.task_alt),
              title: Text(S.newTask),
              onTap: () {
                Navigator.pop(context);
                _showDispatchDialog();
              },
            ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 2: Add _showAgentCreateDialog**

```dart
void _showAgentCreateDialog() {
    showDialog(
      context: context,
      builder: (_) => _AgentCreateDialog(
        onCreated: (name, provider) async {
          final server = ref.read(serverProvider).server;
          if (server == null) return;
          final api = ApiClient(baseUrl: server.url, token: server.token);
          final resp = await api.createSession(
            name: name,
            type: 'agent',
            provider: provider,
          );
          final id = resp['id'] as String?;
          if (id != null && mounted) {
            context.push('/agent/$id');
          }
        },
      ),
    );
  }
```

- [ ] **Step 3: Add _showNameDialog for terminals**

```dart
void _showNameDialog(SessionKind kind) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(S.newTerminal),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: S.name,
            hintText: 'e.g. Build Server',
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(S.cancel)),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _createSession(kind, name: controller.text.trim());
            },
            child: Text(S.create),
          ),
        ],
      ),
    );
  }
```

Update `_createSession` to accept an optional `name` parameter instead of auto-generating.

- [ ] **Step 4: Create _AgentCreateDialog widget**

Add as a private widget in `home_screen.dart` (after the existing helper widgets):

```dart
class _AgentCreateDialog extends StatefulWidget {
  final Future<void> Function(String name, String provider) onCreated;
  const _AgentCreateDialog({required this.onCreated});
  @override
  State<_AgentCreateDialog> createState() => _AgentCreateDialogState();
}

class _AgentCreateDialogState extends State<_AgentCreateDialog> {
  final _nameController = TextEditingController();
  String _provider = 'claude-code';

  @override
  void dispose() { _nameController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.newAgent),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: S.name,
              hintText: 'e.g. Frontend Dev',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Text(S.selectAgent, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(label: const Text('Claude Code'), selected: _provider == 'claude-code',
                onSelected: (_) => setState(() => _provider = 'claude-code')),
              ChoiceChip(label: const Text('Codex CLI'), selected: _provider == 'codex',
                onSelected: (_) => setState(() => _provider = 'codex')),
              ChoiceChip(label: const Text('Gemini CLI'), selected: _provider == 'gemini',
                onSelected: (_) => setState(() => _provider = 'gemini')),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(S.cancel)),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim().isEmpty
                ? _provider == 'claude-code' ? 'Claude Code' : _provider
                : _nameController.text.trim();
            Navigator.pop(context);
            widget.onCreated(name, _provider);
          },
          child: Text(S.create),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Verify build**

Run: `cd client && flutter analyze lib/screens/home_screen.dart`

- [ ] **Step 6: Commit**

```bash
git add client/lib/screens/home_screen.dart
git commit -m "feat(client): agent creation dialog with name and provider selection"
```

---

## Task 8: Client — Dispatch dialog with grouped agents + new-agent option

**Files:**
- Modify: `client/lib/widgets/dispatch_dialog.dart`

- [ ] **Step 1: Rewrite DispatchDialog**

Expand the agent selection to group by provider and add a "New agent" section:

```dart
class _DispatchDialogState extends State<DispatchDialog> {
  AgentStatusInfo? _selectedAgent;
  String? _newAgentProvider; // non-null if user chose "new agent"
  final _titleController = TextEditingController();
  final _promptController = TextEditingController();
  String _priority = 'p1';

  // ... dispose unchanged ...

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Group agents by provider
    final grouped = <String, List<AgentStatusInfo>>{};
    for (final a in widget.agents) {
      grouped.putIfAbsent(a.provider, () => []).add(a);
    }

    return AlertDialog(
      title: Text(S.newTask),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.selectAgent, style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              // Grouped existing agents
              ...grouped.entries.map((entry) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: Text(entry.key, style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline)),
                  ),
                  Wrap(
                    spacing: 8,
                    children: entry.value.map((agent) {
                      final selected = _selectedAgent?.sessionId == agent.sessionId && _newAgentProvider == null;
                      return ChoiceChip(
                        label: Text(agent.name),
                        selected: selected,
                        onSelected: (_) => setState(() { _selectedAgent = agent; _newAgentProvider = null; }),
                      );
                    }).toList(),
                  ),
                ],
              )),
              const Divider(height: 16),
              // New agent option
              Text('New agent', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
              Wrap(
                spacing: 8,
                children: ['claude-code', 'codex', 'gemini'].map((p) {
                  final selected = _newAgentProvider == p;
                  return ChoiceChip(
                    label: Text(p),
                    selected: selected,
                    onSelected: (_) => setState(() { _newAgentProvider = p; _selectedAgent = null; }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              // Title, prompt, priority — unchanged from current implementation
              TextField(controller: _titleController, decoration: InputDecoration(labelText: S.taskTitle, border: const OutlineInputBorder(), isDense: true), onChanged: (_) => setState(() {})),
              const SizedBox(height: 8),
              TextField(controller: _promptController, decoration: InputDecoration(labelText: S.taskDescription, border: const OutlineInputBorder(), isDense: true), maxLines: 3),
              const SizedBox(height: 8),
              Row(children: [
                Text(S.priority, style: theme.textTheme.labelMedium),
                const SizedBox(width: 8),
                SegmentedButton<String>(
                  segments: const [ButtonSegment(value: 'p0', label: Text('P0')), ButtonSegment(value: 'p1', label: Text('P1')), ButtonSegment(value: 'p2', label: Text('P2'))],
                  selected: {_priority},
                  onSelectionChanged: (v) => setState(() => _priority = v.first),
                ),
              ]),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(S.cancel)),
        FilledButton(
          onPressed: (_selectedAgent == null && _newAgentProvider == null) || _titleController.text.trim().isEmpty ? null : () {
            widget.onDispatch(
              _selectedAgent?.name,       // null if new-agent path
              _newAgentProvider,           // null if existing-agent path
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

- [ ] **Step 2: Update onDispatch callback signature**

Change the callback from `(String targetAgent, String title, String prompt, String priority)` to:

```dart
final void Function(String? targetAgent, String? provider, String title, String prompt, String priority) onDispatch;
```

Update all callers in `home_screen.dart`, `agent_screen.dart`, `office_screen.dart` to pass `provider` to `createTask`.

- [ ] **Step 3: Verify build**

Run: `cd client && flutter analyze`

- [ ] **Step 4: Commit**

```bash
git add client/lib/widgets/dispatch_dialog.dart client/lib/screens/home_screen.dart \
       client/lib/screens/agent_screen.dart client/lib/screens/office_screen.dart
git commit -m "feat(client): dispatch dialog with grouped agents and new-agent-by-provider option"
```

---

## Task 9: Slash commands filtered by provider

**Files:**
- Modify: `client/lib/providers/settings_provider.dart`
- Modify: `client/lib/screens/home_screen.dart` (QuickMessageSheet `_onInputChanged`)
- Modify: `client/lib/screens/agent_screen.dart` (input handler)

- [ ] **Step 1: Add providers filter to builtin commands**

In `settings_provider.dart`, change the builtin command format to include a `providers` key:

```dart
static const _kDefaultBuiltinCommands = [
  {'name': 'help', 'description': 'Show help', 'providers': ''},           // universal
  {'name': 'compact', 'description': 'Compact conversation', 'providers': 'claude-code'},
  {'name': 'model', 'description': 'Switch model', 'providers': 'claude-code'},
  {'name': 'clear', 'description': 'Clear context', 'providers': 'claude-code'},
  // ... etc
];
```

Empty `providers` means universal. Comma-separated for multiple providers.

- [ ] **Step 2: Filter builtins when merging**

In `_onInputChanged` (both home_screen.dart and agent_screen.dart), when building the merged command list, filter builtins by the current session's provider:

```dart
final sessionProvider = widget.agentSession.connection.provider; // or pass as parameter
final builtins = ref.read(settingsProvider).builtinSlashCommands
    .where((m) {
      final providers = m['providers'] ?? '';
      return providers.isEmpty || providers.split(',').contains(sessionProvider);
    })
    .map((m) => SlashCommand(name: m['name']!, description: m['description']!))
    .toList();
```

- [ ] **Step 3: Verify build**

Run: `cd client && flutter analyze`

- [ ] **Step 4: Commit**

```bash
git add client/lib/providers/settings_provider.dart client/lib/screens/home_screen.dart \
       client/lib/screens/agent_screen.dart
git commit -m "feat(client): filter slash commands by agent provider type"
```

---

## Task 10: Office area — InteractiveViewer + provider grouping layout

**Files:**
- Modify: `client/lib/widgets/office_painter.dart:62-78`
- Modify: `client/lib/screens/office_screen.dart:70-191`
- Modify: `client/lib/screens/home_screen.dart:224-307`

- [ ] **Step 1: Rewrite slotPosition for grouped layout**

Replace `slotPosition` with a grouped layout function:

```dart
/// Layout result for a group of agents.
class GroupLayout {
  final String provider;
  final String displayName;
  final double yOffset; // top of this group in the canvas
  final double height;  // total height of this group including header
  final List<Offset> positions; // center positions of each agent in this group
}

/// Compute grouped layout for all agents.
List<GroupLayout> computeGroupedLayout(List<AgentStatusInfo> agents, double canvasWidth) {
  const slotW = 140.0;
  const slotH = 150.0;
  const headerH = 32.0;
  const groupPadding = 16.0;

  // Group by provider
  final grouped = <String, List<AgentStatusInfo>>{};
  for (final a in agents) {
    grouped.putIfAbsent(a.provider, () => []).add(a);
  }

  final layouts = <GroupLayout>[];
  double currentY = groupPadding;

  for (final entry in grouped.entries) {
    final count = entry.value.length;
    final cols = (canvasWidth / slotW).floor().clamp(1, count);
    final rows = (count / cols).ceil();
    final groupHeight = headerH + rows * slotH;

    final positions = <Offset>[];
    for (var i = 0; i < count; i++) {
      final row = i ~/ cols;
      final col = i % cols;
      positions.add(Offset(
        col * slotW + slotW / 2,
        currentY + headerH + row * slotH + slotH / 2,
      ));
    }

    layouts.add(GroupLayout(
      provider: entry.key,
      displayName: _providerDisplayName(entry.key),
      yOffset: currentY,
      height: groupHeight,
      positions: positions,
    ));

    currentY += groupHeight + groupPadding;
  }
  return layouts;
}

String _providerDisplayName(String id) {
  switch (id) {
    case 'claude-code': return 'Claude Code';
    case 'codex': return 'Codex CLI';
    case 'gemini': return 'Gemini CLI';
    default: return id;
  }
}
```

- [ ] **Step 2: Wrap office in InteractiveViewer**

In both `office_screen.dart` and `home_screen.dart` `_buildWorkspace`, replace the LayoutBuilder + CustomPaint + Stack with:

```dart
LayoutBuilder(
  builder: (context, constraints) {
    final layouts = computeGroupedLayout(agentList, constraints.maxWidth);
    final totalHeight = layouts.isEmpty ? constraints.maxHeight
        : layouts.last.yOffset + layouts.last.height + 16;
    final contentW = max(constraints.maxWidth, 400.0);
    final contentH = max(constraints.maxHeight, totalHeight);

    return InteractiveViewer(
      boundaryMargin: const EdgeInsets.all(100),
      minScale: 0.4,
      maxScale: 2.0,
      constrained: false,
      child: SizedBox(
        width: contentW,
        height: contentH,
        child: CustomPaint(
          painter: OfficePainter(
            backgroundColor: bgStart,
            backgroundColorEnd: bgEnd,
            gridColor: gridLineColor,
            groups: layouts, // paint group headers
          ),
          child: Stack(
            children: _buildAgentWidgets(agentList, layouts, ...),
          ),
        ),
      ),
    );
  },
)
```

- [ ] **Step 3: Update OfficePainter to draw group headers**

Add `groups` field to `OfficePainter`. In `paint()`, after drawing the grid, draw each group header:

```dart
for (final group in groups) {
  final textPainter = TextPainter(
    text: TextSpan(text: group.displayName, style: TextStyle(color: gridColor.withOpacity(0.5), fontSize: 12)),
    textDirection: TextDirection.ltr,
  )..layout();
  textPainter.paint(canvas, Offset(12, group.yOffset + 8));
}
```

- [ ] **Step 4: Verify build**

Run: `cd client && flutter analyze`

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/office_painter.dart client/lib/screens/office_screen.dart \
       client/lib/screens/home_screen.dart
git commit -m "feat(client): scrollable office with InteractiveViewer and provider grouping"
```

---

## Task 11: Agent visual identity — head shapes + remove desk

**Files:**
- Modify: `client/lib/widgets/office_painter.dart` (AgentPainter)

- [ ] **Step 1: Update providerColor with brand colors**

```dart
Color providerColor(String provider) {
  switch (provider.toLowerCase()) {
    case 'claude-code':
    case 'claude':
      return const Color(0xFFE87B35); // Anthropic orange
    case 'codex':
    case 'openai':
      return const Color(0xFF10A37F); // OpenAI green
    case 'gemini':
    case 'gemini-cli':
      return const Color(0xFF4285F4); // Google blue
    default:
      return const Color(0xFF9E9E9E); // grey
  }
}
```

- [ ] **Step 2: Add providerHeadShape enum and draw function**

```dart
enum HeadShape { circle, hexagon, diamond, roundedSquare }

HeadShape providerHeadShape(String provider) {
  switch (provider.toLowerCase()) {
    case 'claude-code':
    case 'claude':
      return HeadShape.circle;
    case 'codex':
    case 'openai':
      return HeadShape.hexagon;
    case 'gemini':
    case 'gemini-cli':
      return HeadShape.diamond;
    default:
      return HeadShape.roundedSquare;
  }
}

void drawHead(Canvas canvas, Offset center, double radius, HeadShape shape, Paint paint) {
  switch (shape) {
    case HeadShape.circle:
      canvas.drawCircle(center, radius, paint);
    case HeadShape.hexagon:
      final path = Path();
      for (var i = 0; i < 6; i++) {
        final angle = (i * 60 - 90) * pi / 180;
        final p = Offset(center.dx + radius * cos(angle), center.dy + radius * sin(angle));
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, paint);
    case HeadShape.diamond:
      final path = Path()
        ..moveTo(center.dx, center.dy - radius)
        ..lineTo(center.dx + radius, center.dy)
        ..lineTo(center.dx, center.dy + radius)
        ..lineTo(center.dx - radius, center.dy)
        ..close();
      canvas.drawPath(path, paint);
    case HeadShape.roundedSquare:
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCircle(center: center, radius: radius), Radius.circular(radius * 0.25)),
        paint,
      );
  }
}
```

- [ ] **Step 3: Update AgentPainter to use head shapes and remove desk**

In `AgentPainter.paint()`:
- Replace `_drawFace` circle call with `drawHead(canvas, center, radius, providerHeadShape(agent.provider), paint)`
- Remove `_drawDesk()` call entirely
- Delete the `_drawDesk` method
- Adjust vertical positions: with no desk, shift the head and badge up so agent occupies ~150px height

- [ ] **Step 4: Update slotSize references**

Change `const slotSize = Size(160, 200)` to `const slotSize = Size(140, 150)` in both `home_screen.dart` and `office_screen.dart`.

- [ ] **Step 5: Verify build**

Run: `cd client && flutter analyze`

- [ ] **Step 6: Commit**

```bash
git add client/lib/widgets/office_painter.dart client/lib/screens/home_screen.dart \
       client/lib/screens/office_screen.dart
git commit -m "feat(client): agent head shapes by provider, remove desk, compact layout"
```

---

## Task 12: Debug activity bubble display

**Files:**
- Modify: `server/crates/core/src/agent/manager.rs` (event router)
- Modify: `client/lib/providers/agent_status_provider.dart`

- [ ] **Step 1: Add debug logging on server**

In the event router, after `status_registry.update()`, add a trace log:

```rust
if changed {
    tracing::debug!(
        session_id = %sid,
        status = %activity_status,
        activity_len = activity_text.len(),
        "broadcasting activity change"
    );
    // ... existing publish_control ...
}
```

- [ ] **Step 2: Add debug logging on client**

In `agent_status_provider.dart`, in the WebSocket listener:

```dart
if (type == 'agent_activity') {
    final sessionId = json['session_id'] as String;
    final incomingActivity = json['activity'] as String? ?? '';
    debugPrint('[AgentStatus] $sessionId: status=${json['status']}, activity=${incomingActivity.length > 30 ? '${incomingActivity.substring(0, 30)}...' : incomingActivity}');
    // ... existing update logic ...
}
```

- [ ] **Step 3: Check for empty-string overwrites**

In the event router's activity status matching, ensure `AvailableCommands` and `Progress` events don't broadcast empty activity that overwrites real content. Currently they produce `(AgentActivity::Working, String::new(), None)` — the empty string causes `status_registry.update()` to preserve existing text, which is correct. But verify the `changed` flag: if status is already `Working` and text is preserved (same), `changed` should be `false` and no broadcast should occur.

If `changed` is incorrectly `true` (because of some other field like cost), the broadcast sends empty `activity` which the client preserves. This is fine. The issue is more likely that the broadcast never fires for the initial text.

- [ ] **Step 4: Verify and commit**

Run server with debug logging, create an agent, observe logs.

```bash
git add server/crates/core/src/agent/manager.rs client/lib/providers/agent_status_provider.dart
git commit -m "fix: add debug logging for activity bubble investigation"
```

---

## Execution Order

Tasks 1-3 form the persistence chain (can be done sequentially).
Tasks 4-5 form the dispatch refactor (depends on Task 4).
Task 6 is the provider config (independent).
Tasks 7-9 are client UI changes (depend on Task 6 for provider list).
Tasks 10-11 are office visual changes (independent of other tasks).
Task 12 is a debug/investigation task (independent).

Recommended parallel groups:
- **Group A** (persistence): Tasks 1 → 2 → 3
- **Group B** (dispatch): Tasks 4 → 5
- **Group C** (config): Task 6
- **Group D** (client UI): Tasks 7 → 8 → 9 (after Group C)
- **Group E** (office UX): Tasks 10 → 11
- **Group F** (debug): Task 12
