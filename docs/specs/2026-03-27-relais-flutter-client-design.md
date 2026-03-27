# Relais — Remote Terminal & AI Agent Client

**Date:** 2026-03-27
**Status:** Approved

## Overview

Relais is an independent, cross-platform client for remote terminal access and AI agent interaction. It connects to backend servers via REST API and WebSocket.

Relais is a standalone product with its own identity, not a frontend for any specific backend project. The server-side protocol is documented below; any compatible server implementation works.

**Principle:** Relais handles ALL client-side concerns. Server handles ALL server-side concerns. Clean separation, no overlap.

## Architecture

```
Relais (Flutter Client)              Server (any compatible impl)
┌────────────────────────┐           ┌────────────────────────┐
│ iOS / Android / macOS  │  REST +   │ Linux / macOS / Docker │
│ Windows / Web          │◄─────────►│                        │
│                        │ WebSocket │ Terminal / AI Agent     │
│ Scan QR or enter URL   │           │ Plugins / Tunnel       │
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

## Design System

**Material 3** with `useMaterial3: true`:
- Dynamic color (Material You) where supported
- M3 elevation, shapes, and typography
- `ColorScheme.fromSeed()` for consistent theming
- Adaptive layout: `NavigationBar` (mobile), `NavigationRail` (tablet), `NavigationDrawer` (desktop)
- M3 components: `FilledButton`, `SearchBar`, `SegmentedButton`, `Card.filled`, etc.

## Features

### P1: Core (MVP)

1. **Server Connection**
   - Enter server URL + token manually
   - Scan QR code (camera on mobile, paste on desktop)
   - Save multiple servers with friendly names
   - Connection status indicator (M3 badge)
   - Auto-reconnect on disconnect

2. **Session List**
   - List all sessions (terminal + agent)
   - Create new terminal or agent session
   - Delete sessions (swipe-to-dismiss on mobile)
   - Session status chip (running/idle/crashed)

3. **Terminal View**
   - Remote terminal rendering (ANSI escape sequences)
   - Keyboard input (including special keys)
   - Mobile: virtual key bar (Ctrl, Tab, Esc, arrows)
   - Desktop: native keyboard passthrough
   - Fit terminal to screen size

4. **Agent Chat**
   - Chat interface with message bubbles
   - Message types: user, agent text, thinking, tool use, tool result, progress, error, turn complete
   - Messages from other sources shown with source label
   - Markdown rendering for agent text
   - Send messages via text field

### P2: Enhanced

5. **Plugin Status** — Connection badges for integrations
6. **Tunnel URL** — Display and copy-to-clipboard
7. **Theming** — Dark/light, match system or manual toggle
8. **Notifications** — Push notifications for agent events

### P3: Polish

9. **Multi-server Dashboard** — Overview of all saved servers
10. **Session Tabs** — Quick switch between active sessions
11. **Settings** — Font size, theme, notification preferences

## Tech Stack

| Concern | Package |
|---------|---------|
| UI framework | Flutter + Material 3 |
| Terminal rendering | `xterm` (dart, Canvas-based) |
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
│   ├── app.dart                       # MaterialApp, router, M3 theme
│   ├── models/
│   │   ├── server.dart                # Server connection info (url, token, name)
│   │   ├── session.dart               # Session metadata (id, type, status)
│   │   └── agent_message.dart         # Chat message types
│   ├── services/
│   │   ├── api_client.dart            # REST API client (dio)
│   │   ├── terminal_connection.dart   # Terminal WebSocket (binary)
│   │   └── agent_connection.dart      # Agent WebSocket (JSON)
│   ├── providers/
│   │   ├── server_provider.dart       # Server list, current connection
│   │   ├── session_provider.dart      # Session list, CRUD
│   │   ├── terminal_provider.dart     # Terminal data stream
│   │   └── agent_provider.dart        # Agent messages stream
│   ├── screens/
│   │   ├── connect_screen.dart        # Server URL input / QR scan
│   │   ├── home_screen.dart           # Session list + adaptive navigation
│   │   ├── terminal_screen.dart       # Full-screen terminal
│   │   └── agent_screen.dart          # Agent chat interface
│   ├── widgets/
│   │   ├── terminal_view.dart         # xterm widget wrapper
│   │   ├── agent_chat.dart            # Chat message list
│   │   ├── message_bubble.dart        # Individual message rendering
│   │   ├── session_card.dart          # Session list item (M3 Card)
│   │   ├── special_key_bar.dart       # Mobile virtual key bar
│   │   └── connection_indicator.dart  # Server status badge
│   └── theme/
│       └── app_theme.dart             # M3 theme (seed color, dark/light)
├── pubspec.yaml
└── README.md
```

## Server Protocol

Relais communicates with any server implementing this protocol.

### REST API

All requests include `Authorization: Bearer <token>` header.

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/v1/status` | Server health check |
| GET | `/api/v1/sessions` | List all sessions |
| POST | `/api/v1/sessions` | Create session |
| DELETE | `/api/v1/sessions/{id}` | Delete session |
| GET | `/api/v1/plugins` | Plugin status |
| GET | `/api/v1/tunnel/status` | Tunnel URL |

### WebSocket

| Path | Protocol | Purpose |
|------|----------|---------|
| `/ws/terminal?session=X&token=T` | Binary frames | Terminal I/O |
| `/ws/agent?session=X&token=T` | JSON frames | Agent chat |
| `/ws/status?token=T` | JSON frames | Real-time status |

### Agent WebSocket Messages (server → client)

| type | Fields | Display |
|------|--------|---------|
| `status` | status, session_id | Connection indicator |
| `user_message` | text, source, seq | User bubble with source label |
| `text` | content, streaming, seq | Agent text (markdown) |
| `thinking` | content, seq | Collapsed thinking block |
| `tool_use` | name, id, input, seq | Tool invocation card |
| `tool_result` | output, is_error, id, seq | Tool result (collapsible) |
| `progress` | message, seq | Progress indicator |
| `turn_complete` | cost_usd, seq | Done marker |
| `error` | message, severity, guidance, seq | Error alert |

### Agent WebSocket Messages (client → server)

| type | Fields |
|------|--------|
| `message` | text |
| `cancel` | (none) |

## Phased Delivery

**P1 (MVP):** Server connection + session list + terminal view + agent chat
**P2:** Plugin status, tunnel URL, theming, notifications
**P3:** Multi-server dashboard, session tabs, settings

Each phase is a separate plan → implementation cycle.
