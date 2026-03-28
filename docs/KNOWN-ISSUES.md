# Known Issues — 2026-03-28

## Critical

### 1. Bottom panel overflow on Home screen
- AnimatedContainer 的高度计算有问题，导致 "BOTTOM OVERFLOWED" 错误
- 需要检查 expandedHeight 计算和 Column 约束

### 2. Tasks not consumed by agents
- `get_next_executable()` 现在要求 `target_agent.is_some()`，但创建任务时 target_agent 可能没正确传入
- 需要验证 `POST /api/v1/tasks` → Task 创建 → TaskDispatcher 消费 的全链路

### 3. Task navigation to wrong agent
- 点击任务跳转的是 `task.sessionId`（dispatcher 创建的 "task-xxx" session），不是目标 agent 的 session
- 需要通过 agent name 查找正确的 session

### 4. Slash command menu height (QuickMessageSheet)
- 在 QuickMessageSheet 的 ModalBottomSheet 内，slash command overlay 可能不受 240px 限制
- BottomSheet 的 overlay context 和主页面不同

## Important

### 5. Session persistence
- 服务端重启后所有终端和 agent 会话丢失
- 需要持久化 session 元数据（name, provider, cwd, status）
- 重启后重建 agent 连接

### 6. Real-time updates 仍有延迟
- AgentStatusProvider 已改为 WebSocket 驱动，但 agent activity 更新可能仍有延迟
- 需要验证 server 端 AgentActivityChanged 事件的 throttle 逻辑

### 7. Last message display
- Agent 头像上的最后消息气泡有时不显示
- AgentStatusProvider 的 WebSocket handler 需要正确保留 activity
