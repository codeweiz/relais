# Phase 2: @ Task Dispatch + Office Enhancement + Task Visualization

**Date:** 2026-03-28
**Status:** Approved
**Scope:** @ task dispatch in agent chat, task completion notification, Office panel task queue
**Phase:** 2 of 3 (Phase 1: Office visualization, Phase 3: full dashboard)

## Overview

Enable task dispatch from agent chat via `@agent-name` syntax and UI button, with completion notification callback. Enhance the Office panel with task-aware agent bubbles and a collapsible task queue. All backed by the existing TaskPool server infrastructure.

## Design

### 1. @ Task Dispatch (Agent Chat)

#### 1.1 @ Syntax Parsing (Client-side)

When user types `@name 任务描述` in the agent chat input:

1. Client detects message starts with `@`
2. Extracts target agent name (text between `@` and first space)
3. Extracts task description (text after first space)
4. Validates target agent exists (via cached agent status list)
5. Calls `POST /api/v1/tasks`:
```json
{
  "title": "<task description, first 50 chars>",
  "prompt": "<full task description>",
  "priority": "p1",
  "cwd": "<current agent's cwd>",
  "target_agent": "<target agent name>"
}
```
6. Does NOT send message to current agent
7. Inserts a local system message in current chat: "📋 已派发给 <name>：<description>"

If target agent name doesn't match any running agent → show error toast, don't create task.

#### 1.2 @ Autocomplete

When user types `@`, show a popup menu listing all running agents (from `AgentStatusProvider`). Same adaptive UI pattern as slash commands:
- Desktop: OverlayEntry above input, keyboard nav
- Mobile: BottomSheet with tap selection

Each item shows: agent name + provider + status indicator.

Selection fills `@name ` into the input (with trailing space), user continues typing the task description.

#### 1.3 UI Dispatch Button

Add a `@` IconButton to the left of the input field. Tap opens a `DispatchDialog`:
- Step 1: Select target agent (list from AgentStatusProvider)
- Step 2: Enter task description
- Step 3: Select priority (P0/P1/P2, default P1)
- Step 4: Confirm → calls same `POST /api/v1/tasks` API

### 2. Task Completion Notification

#### 2.1 Server-side Event

When TaskDispatcher detects a task is complete (agent turn_complete or session ends):

1. Read the target agent's last text response (from event history)
2. Truncate to 200 characters as summary
3. Broadcast a new control event:

```rust
ControlEvent::TaskCompleted {
    task_id: String,
    source_session_id: String,  // session that dispatched the task
    target_name: String,        // agent that executed the task
    success: bool,
    summary: String,            // last agent response, truncated
}
```

#### 2.2 Client-side Notification

The `AgentSession` subscribes to the global `/ws/status` WebSocket. When a `TaskCompleted` event arrives whose `source_session_id` matches the current session:

Insert a notification message into the chat:
```
✅ gemini 完成了任务：修复认证 bug
> 已修复 JWT 验证逻辑，所有测试通过...
```
Or on failure:
```
❌ gemini 任务失败：修复认证 bug
> Error: Cannot find module 'jsonwebtoken'...
```

Message type: `AgentMessageType.system` (or a new type if needed) — rendered with distinct system message styling.

### 3. Office Panel Enhancement

#### 3.1 Agent Bubble Enhancement

When an agent is executing a task (task status = Running, linked via session_id):
- Bubble shows task title (`📋 修复认证 bug`) instead of raw activity text
- If no linked task, show original activity as before

Data source: merge `GET /api/v1/agents/status` with `GET /api/v1/tasks` — match task.session_id to agent.session_id.

#### 3.2 Task Queue Panel (Bottom Collapsible)

A collapsible panel at the bottom of the Office screen:

**Collapsed state:** Single bar showing `📋 任务队列 (N)` + expand icon. N = count of non-terminal tasks.

**Expanded state:** Scrollable list of non-terminal tasks (Queued + Running + NeedsReview):

Each row:
- Priority chip: P0 (red), P1 (yellow), P2 (green)
- Task title (truncated)
- Target agent name or "待分配" (unassigned)
- Status indicator: 🟢 Running, 🟡 Queued, 🔵 NeedsReview
- Tap: if Running → navigate to agent chat; if Queued/unassigned → show assign dialog

**"+ 新建任务" button:** Opens same DispatchDialog as the @ button in chat.

**Key rule:** Unassigned tasks (no target agent specified) stay in queue and are NOT auto-dispatched. Only tasks with a specified target agent are eligible for TaskDispatcher auto-scheduling.

#### 3.3 Task Data Provider

New `TaskProvider` (Riverpod StateNotifier):
- Fetches `GET /api/v1/tasks` on Office screen mount
- Periodic refresh every 5 seconds
- Listens to `/ws/status` for `TaskCompleted` events to update locally
- Exposes `List<TaskInfo>` to UI

### 4. Server Changes

#### 4.1 TaskDispatcher Modification

The existing TaskDispatcher in `task_pool/` auto-assigns tasks to idle agents. Modify:

- `get_next_executable()` must skip tasks where `target_agent` is empty/null
- Only tasks with an explicit `target_agent` value are eligible for auto-dispatch
- When dispatching, create an agent session with the specified provider or find the existing session matching the target name

#### 4.2 Task Create API Enhancement

The existing `POST /api/v1/tasks` endpoint needs to accept an optional `target_agent` field:

```json
{
  "title": "...",
  "prompt": "...",
  "priority": "p1",
  "target_agent": "gemini"  // optional — if omitted, task stays unassigned
}
```

The `target_agent` field is stored on the Task struct.

#### 4.3 TaskCompleted Event

Add to `ControlEvent` in `events.rs`:

```rust
TaskCompleted {
    task_id: String,
    source_session_id: String,
    target_name: String,
    success: bool,
    summary: String,
}
```

Serialize in `ws/status.rs` as:
```json
{
  "type": "task_completed",
  "task_id": "...",
  "source_session_id": "...",
  "target_name": "...",
  "success": true,
  "summary": "所有测试通过..."
}
```

## Out of Scope

- Task dependency visualization (connection lines)
- Task drag-and-drop reordering
- Agent-to-agent real-time messaging (only task dispatch + result callback)
- Task editing after creation (cancel and recreate instead)
- Auto-creating agents when @ targets a non-existent agent (show error instead)
- Task history / completed task archive in Office

## Files Changed

| File | Action | Purpose |
|------|--------|---------|
| `server/crates/core/src/events.rs` | Modify | Add `TaskCompleted` control event |
| `server/crates/core/src/task_pool/` | Modify | Skip unassigned tasks in dispatcher, add `target_agent` field |
| `server/crates/core/src/agent/manager.rs` | Modify | Capture agent last response for task summary |
| `server/crates/server/src/api/sessions.rs` | Modify | Accept `target_agent` in task creation |
| `server/crates/server/src/ws/status.rs` | Modify | Serialize `TaskCompleted` event |
| `client/lib/models/task.dart` | Create | Task data model |
| `client/lib/providers/task_provider.dart` | Create | Global task list provider |
| `client/lib/widgets/dispatch_dialog.dart` | Create | Task dispatch form dialog |
| `client/lib/widgets/agent_picker_menu.dart` | Create | @ autocomplete menu (reuses adaptive pattern) |
| `client/lib/widgets/task_queue_panel.dart` | Create | Office bottom collapsible task queue |
| `client/lib/screens/agent_screen.dart` | Modify | @ detection, autocomplete, dispatch, receive notifications |
| `client/lib/screens/office_screen.dart` | Modify | Integrate task queue panel, enhance agent bubbles |
| `client/lib/services/api_client.dart` | Modify | Add task CRUD API methods |
| `client/lib/l10n/strings.dart` | Modify | Add dispatch/task i18n strings |

## Testing

1. **Server:** Verify TaskDispatcher skips unassigned tasks
2. **Server:** Verify `TaskCompleted` event broadcast with correct summary
3. **Client:** @ parsing extracts name and description correctly
4. **Client:** DispatchDialog creates task via API
5. **Client:** TaskQueuePanel renders tasks from API
6. **Manual E2E:** Create 2 agents, dispatch task from agent A to agent B via @, verify task appears in Office queue, verify completion notification in agent A's chat
