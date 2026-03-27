# Relais — Flutter RTB Client

**Date:** 2026-03-27
**Status:** Approved

## Overview

Relais is a cross-platform Flutter client for RTB (Remote Terminal Bridge). It connects to one or more RTB servers via REST API and WebSocket, providing terminal access and AI agent interaction.

**Principle:** Flutter handles ALL client-side concerns. Rust handles ALL server-side concerns. No overlap.

## Architecture

```
Flutter Client (relais)              Rust Server (rtb-cli)
┌────────────────────────┐           ┌────────────────────────┐
│ iOS / Android / macOS  │  REST +   │ Linux / macOS / Docker │
│ Windows / Web          │◄─────────►│                        │
│                        │ WebSocket │ PTY / Agent / Plugin   │
│ Scan QR or enter URL   │           │ Tunnel / Notification  │
│ to connect             │           │                        │
└────────────────────────┘           └────────────────────────┘
```

## Target Platforms

| Platform | Build Target |
|----------|-------------|
| iOS | Flutter iOS |
| Android | Flutter Android |
| macOS | Flutter macOS desktop |
| Windows | Flutter Windows desktop |
| Web | Flutter Web |

Linux desktop is NOT a target — Linux users run `rtb-cli` (server) and connect via mobile/web/other desktop.

## Features

### P1: Core (MVP)

1. **Server Connection**
   - Enter server URL + token manually
   - Scan QR code (camera on mobile, paste on desktop)
   - Save multiple servers, quick switch
   - Connection status indicator
   - Auto-reconnect on disconnect

2. **Session List**
   - List all sessions (terminal + agent) from `GET /api/v1/sessions`
   - Create new terminal or agent session
   - Delete sessions
   - Show session status (running/idle/crashed)

3. **Terminal View**
   - Connect via `WS /ws/terminal?session=X`
   - Render terminal output (ANSI escape sequence processing)
   - Send keyboard input (including special keys)
   - Mobile: virtual keyboard with special key bar (Ctrl, Tab, Esc, arrows)
   - Desktop: native keyboard passthrough
   - Fit terminal to screen size

4. **Agent Chat**
   - Connect via `WS /ws/agent?session=X`
   - Display message types: user message, agent text, thinking, tool use, tool result, progress, error, turn complete
   - Send messages to agent
   - Show messages from other sources (Feishu) with `[source]` prefix
   - Markdown rendering for agent text

### P2: Enhanced

5. **Plugin Status** — Show Feishu/Tunnel connection status
6. **Tunnel URL** — Display and copy public tunnel URL
7. **Dark/Light Theme** — Match system or manual toggle
8. **Notifications** — Push notifications for agent completion, errors

### P3: Polish

9. **Multi-server Dashboard** — Overview of all saved servers
10. **Session Tabs** — Switch between multiple terminal/agent sessions
11. **Settings** — Font size, theme, notification preferences

## Tech Stack

| Concern | Package |
|---------|---------|
| Terminal rendering | `xterm` (dart package, Canvas-based) |
| WebSocket | `web_socket_channel` |
| HTTP | `dio` |
| State management | `riverpod` |
| Routing | `go_router` |
| QR scanning | `mobile_scanner` |
| Local storage | `shared_preferences` |
| Markdown | `flutter_markdown` |

## Project Structure

```
relais/
├── lib/
│   ├── main.dart
│   ├── app.dart                    # MaterialApp, router, theme
│   ├── models/
│   │   ├── server.dart             # Server connection info
│   │   ├── session.dart            # Session metadata
│   │   └── agent_message.dart      # Agent chat message types
│   ├── services/
│   │   ├── rtb_api.dart            # REST API client (dio)
│   │   ├── terminal_ws.dart        # Terminal WebSocket (binary)
│   │   └── agent_ws.dart           # Agent WebSocket (JSON)
│   ├── providers/
│   │   ├── server_provider.dart    # Current server, connection state
│   │   ├── session_provider.dart   # Session list, CRUD
│   │   ├── terminal_provider.dart  # Terminal data stream
│   │   └── agent_provider.dart     # Agent messages stream
│   ├── screens/
│   │   ├── connect_screen.dart     # Server URL input / QR scan
│   │   ├── home_screen.dart        # Session list + navigation
│   │   ├── terminal_screen.dart    # Full-screen terminal
│   │   └── agent_screen.dart       # Agent chat interface
│   ├── widgets/
│   │   ├── terminal_view.dart      # xterm widget wrapper
│   │   ├── agent_chat.dart         # Chat bubble list
│   │   ├── agent_message_bubble.dart  # Individual message rendering
│   │   ├── session_card.dart       # Session list item
│   │   ├── special_key_bar.dart    # Mobile virtual key bar
│   │   └── qr_scanner.dart         # QR code scanner
│   └── theme/
│       └── app_theme.dart          # Dark/light theme definitions
├── pubspec.yaml
└── README.md
```

## RTB Server API Surface (client needs)

### REST API

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/v1/status` | Server health check |
| GET | `/api/v1/sessions` | List all sessions |
| POST | `/api/v1/sessions` | Create session |
| DELETE | `/api/v1/sessions/{id}` | Delete session |
| GET | `/api/v1/plugins` | Plugin status |
| GET | `/api/v1/tunnel/status` | Tunnel URL |

All requests include `Authorization: Bearer <token>` header.

### WebSocket

| Path | Protocol | Purpose |
|------|----------|---------|
| `/ws/terminal?session=X&token=T` | Binary frames (PTY I/O) | Terminal |
| `/ws/agent?session=X&token=T` | JSON frames | Agent chat |
| `/ws/status?token=T` | JSON frames | Real-time status updates |

### Agent WebSocket Message Types (server → client)

| type | Fields | Display |
|------|--------|---------|
| `status` | status, session_id | Connection indicator |
| `user_message` | text, source, seq | User bubble with [source] |
| `text` | content, streaming, seq | Agent text (markdown) |
| `thinking` | content, seq | Collapsed thinking block |
| `tool_use` | name, id, input, seq | Tool invocation card |
| `tool_result` | output, is_error, id, seq | Tool result (collapsible) |
| `progress` | message, seq | Progress indicator |
| `turn_complete` | cost_usd, seq | Done marker |
| `error` | message, severity, guidance, seq | Error alert |

### Agent WebSocket Message Types (client → server)

| type | Fields |
|------|--------|
| `message` | text |
| `cancel` | (none) |

## Phased Delivery

**P1 (MVP):** Server connection + session list + terminal view + agent chat
**P2:** Plugin status, tunnel URL, theming, notifications
**P3:** Multi-server dashboard, session tabs, settings

Each phase is a separate spec → plan → implementation cycle.
