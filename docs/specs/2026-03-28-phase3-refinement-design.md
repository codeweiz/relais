# Phase 3: Refinement — Task/Agent Model, Persistence, Office UX

> Date: 2026-03-28
> Status: Draft
> Depends on: phase2-task-dispatch, multi-agent-office, slash-commands

## Overview

Three areas of improvement based on real usage feedback:

1. **Task/Agent Model Refactor** — tasks dispatch to existing agents, not temporary ones
2. **Agent Session Persistence** — agent conversations survive server restart via CLI `--resume`
3. **Office Area UX** — scrollable canvas, provider-based grouping, visual identity per agent type

Terminal persistence is explicitly out of scope (PTY processes cannot survive restarts).

---

## 1. Task/Agent Model Refactor

### 1.1 Dispatch Logic

**Current**: Every task creates a new agent process (`task-{id}` session). `target_agent` is just a filter label.

**New**: Two paths based on what the user specifies:

| User specifies | Behavior |
|----------------|----------|
| Existing agent name (e.g. "Claude") | Send task prompt directly to that agent's session via `send_message()`. No new process. |
| Agent type only (e.g. "codex") | Create a new agent of that type. Task links to it. Agent persists after task completes. |

**Server changes** (`scheduler.rs` `dispatch_tick`):

```
get_next_executable() returns task
  ├─ task.target_agent matches running agent name?
  │   ├─ YES → send_message(agent_session_id, task_prompt)
  │   │        set task.session_id = agent_session_id
  │   │        track turn completion via TurnComplete event
  │   └─ NO  → check task.provider field
  │        ├─ provider set → create_agent(new_id, task.name, provider, ...)
  │        │                 send_message(new_id, task_prompt)
  │        └─ neither → task stays queued (unassigned)
```

**API changes** (`AddTaskRequest`):

```rust
pub struct AddTaskRequest {
    pub title: String,
    pub prompt: String,
    pub priority: Option<String>,
    pub target_agent: Option<String>,   // existing agent name
    pub provider: Option<String>,       // NEW: agent type for new-agent path
    pub cwd: Option<String>,
    pub depends_on: Vec<String>,
    pub source_session_id: Option<String>,
}
```

**Task completion tracking** (for reused agents):
- `TaskDispatcher` maintains a `HashMap<SessionId, TaskId>` mapping active agent sessions to their current task
- When dispatching to an existing agent: insert `(agent_session_id, task_id)` into the map
- On `AgentStatusChanged(Idle)` for that session: look up pending task, mark as completed/needs_review
- On `AgentStatusChanged(Crashed)` for that session: mark task as failed
- One agent handles one task at a time — if the agent is already processing a task, new tasks queue until the current one completes

### 1.2 Agent Type System

**Supported providers** (extensible):

| Provider ID | Display Name | CLI Command |
|-------------|-------------|-------------|
| `claude-code` | Claude Code | `claude` |
| `codex` | Codex CLI | `codex` |
| `gemini` | Gemini CLI | `gemini` |

Provider registry stored in server config (`config.toml`):

```toml
[[agent.providers]]
id = "claude-code"
name = "Claude Code"
command = "claude"

[[agent.providers]]
id = "codex"
name = "Codex CLI"
command = "codex"

[[agent.providers]]
id = "gemini"
name = "Gemini CLI"
command = "gemini"
```

Remove the current `agent.default_provider` config — users choose at creation time.

### 1.3 Client: Agent Creation Dialog

Replace the current instant-create flow with a dialog:

- **Name field**: optional text input, placeholder "e.g. Frontend Dev". If empty, auto-generate like "Claude Code #3"
- **Type selector**: ChoiceChips showing available providers from server config. Default: Claude Code
- **Create button**: calls `POST /api/v1/sessions` with name + provider

### 1.4 Client: Dispatch Dialog Changes

- **"Select agent" section**: shows running agents grouped by provider
- **"New agent" option**: at the bottom, lets user pick a provider type → task gets `provider` field instead of `target_agent`

### 1.5 Slash Commands per Agent Type

Each agent process reports its own commands via `AvailableCommands` event — this already works per-session. The change needed:

- **Builtin commands** in client settings: add a `providers` filter field to each builtin command
- Client filters builtins by the current session's provider before merging with dynamic commands
- Example: `/compact` is Claude Code only, `/help` is universal

---

## 2. Agent Session Persistence

### 2.1 Architecture

Leverage Claude CLI's built-in `--resume <session_id>` capability. The server's role is only to **store and pass the CLI session ID**.

```
Agent lifecycle:
  start → CLI emits session_id in "system" message
        → server stores in meta.json { acp_session_id: "..." }
        → on TurnComplete, update acp_session_id if changed

  server restart → meta.json preserved on disk
                 → status marked "suspended"

  client reconnects → WebSocket handler reads meta.json
                    → spawns CLI with --resume <acp_session_id>
                    → CLI restores full conversation context internally
                    → client receives event history replay from events.jsonl
```

### 2.2 Server Changes

**`SessionMeta` (types.rs)**: Add field:

```rust
pub struct SessionMeta {
    // ... existing fields ...
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub acp_session_id: Option<String>,
}
```

**`AgentManager` event router**: On `TurnComplete` with `session_id`, update `meta.json`:

```rust
AgentEvent::TurnComplete { session_id, cost_usd } => {
    if let Some(ref cli_sid) = session_id {
        // Persist CLI session ID for resume
        if let Ok(mut meta) = session_store.get_meta(&sid) {
            meta.acp_session_id = Some(cli_sid.clone());
            let _ = session_store.update_meta(&sid, &meta);
        }
    }
}
```

**`AcpBackend::start()`**: Accept optional `resume_session_id` parameter:

```rust
pub async fn start(&mut self, cwd: &Path, resume_session_id: Option<&str>) -> Result<(), String>
```

Pass through to `ClaudeSdk::spawn()` which already supports `--resume`.

**`ws_agent` handler** (resume path): Read `acp_session_id` from meta, pass to `create_agent`:

```rust
let resume_id = meta.acp_session_id.as_deref();
agent_manager.create_agent_with_resume(session_id, name, provider, model, cwd, resume_id)
```

### 2.3 Client Changes

- **Suspended sessions** in the session list show a "suspended" badge
- Tapping a suspended session connects via WebSocket as normal → triggers server-side resume
- Chat history renders from the WebSocket event replay (events.jsonl data sent on connect)
- No special client logic needed — resume is transparent

### 2.4 What About Non-Claude Agents?

- Codex and Gemini may or may not support `--resume`
- If they don't, the agent starts fresh (no conversation context)
- The JSONL history still renders in the client for UI continuity
- This is a graceful degradation, not a failure

---

## 3. Office Area UX

### 3.1 Scrollable Canvas

**Current**: `Stack` sized to screen constraints. Agents overflow and get clipped.

**New**: Wrap in `InteractiveViewer`:

```dart
InteractiveViewer(
  boundaryMargin: const EdgeInsets.all(100),
  minScale: 0.4,
  maxScale: 2.0,
  constrained: false,  // allow content larger than viewport
  child: SizedBox(
    width: contentWidth,
    height: contentHeight,
    child: CustomPaint(
      painter: OfficePainter(...),
      child: Stack(children: agentWidgets),
    ),
  ),
)
```

`contentWidth` and `contentHeight` computed from the grid layout:

```dart
final contentWidth = max(screenWidth, cols * slotW);
final contentHeight = max(screenHeight, totalRows * slotH + groupHeadersHeight);
```

### 3.2 Provider-Based Grouping

Layout algorithm:

1. Group agents by `provider`
2. Each group has a header label (e.g. "Claude Code", "Codex CLI")
3. Within each group: grid layout (same `slotPosition` logic, scoped to group)
4. Groups stack vertically with spacing between them

```
┌─── Claude Code ──────────────────────┐
│  [Agent A]  [Agent B]  [Agent C]     │
│  [Agent D]                           │
├─── Codex CLI ────────────────────────┤
│  [Agent E]  [Agent F]                │
└──────────────────────────────────────┘
```

Group header: painted by `OfficePainter` as a subtle label + divider line.

### 3.3 Agent Visual Identity

Remove the desk. Keep: **head + name badge**.

Different agent types distinguished by **head shape + brand color**:

| Provider | Head Shape | Color | Rationale |
|----------|-----------|-------|-----------|
| Claude Code | Circle | `#E87B35` (Anthropic orange) | Friendly, rounded |
| Codex / OpenAI | Hexagon | `#10A37F` (OpenAI green) | Tech, structured |
| Gemini | Diamond | `#4285F4` (Google blue) | Geometric, balanced |
| Unknown/Custom | Rounded square | `#9E9E9E` (grey) | Neutral fallback |

**Name badge**: shows user-given name (e.g. "Frontend Dev"), NOT the provider type. Provider is conveyed by the shape/color.

**`AgentPainter` changes**:
- Accept `provider` string to determine shape + color
- Remove desk drawing code
- Reduce `slotSize` from `Size(160, 200)` to ~`Size(140, 150)` (no desk = more compact)
- Activity bubble rendering unchanged

### 3.4 Activity Bubble Fix

Known issue: bubble sometimes doesn't display content even after the 10-char filter was removed.

Root cause to investigate during implementation:
- Check if `AgentActivityChanged` events are actually reaching the client for all event types
- Verify `status_registry.update()` returns `changed = true` when activity text updates
- Check client-side: does `agentStatusProvider` correctly update state for the matching sessionId?
- The `activity` field in `AgentStatusInfo` might be getting overwritten by empty strings from intermediate events

---

## Out of Scope

- Terminal session persistence (PTY cannot survive restart)
- Multi-agent collaboration / agent-to-agent communication
- Agent auto-scaling / load balancing
- Plugin integration changes

---

## Migration Notes

- Existing sessions without `acp_session_id` field: treated as non-resumable (fresh start)
- Existing tasks with `session_id` starting with `task-`: these temporary sessions will no longer be created going forward. Old ones remain in the session store but are effectively dead.
- Config migration: existing `agent.default_provider` → removed, no replacement needed
