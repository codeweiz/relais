# Known Issues — 2026-03-28

All issues resolved.

## Resolved

### 1. Bottom panel overflow on Home screen
- **Root cause**: `BoxDecoration.border` adds implicit 1px padding inside Container, reducing child space from 56→55px while inner SizedBox remains 56px
- **Fix**: Moved the border to a separate `Container(height:1)` widget above the panel, removed border from decoration

### 2. Tasks not consumed by agents
- Added `--target-agent` CLI flag
- Fixed pool tests to include `with_target_agent()`
- Added `TaskAdded` control event for real-time client refresh
- Dispatcher now triggers immediate dispatch on `TaskAdded` (no 5s polling wait)

### 3. Task navigation to wrong agent
- Fixed in prior commit — `_navigateToAgent()` looks up agent by name first

### 4. Slash command menu height (QuickMessageSheet)
- Replaced overlay-based menu with inline display inside the bottom sheet Column

### 5. Session persistence
- `session_store.create()` now called on agent and terminal session creation
- Agent events persisted to `events.jsonl` via `session_store.append_event()`
- On startup, suspended agents registered in status registry and listed in API
- WebSocket handler auto-resumes suspended agent sessions on client connect

### 6. Real-time updates delay
- Removed 10-char text filter and conditional broadcast suppression
- All status transitions now broadcast immediately

### 7. Last message display
- Fixed alongside Issue 6 — all text content flows through to clients

### 8. Office area not refreshing after agent creation
- **Root cause**: `agent_manager.create_agent()` never emitted `SessionCreated` event (only terminal sessions did)
- **Fix**: Added `SessionCreated` emission in agent manager, so `agentStatusProvider` refreshes
