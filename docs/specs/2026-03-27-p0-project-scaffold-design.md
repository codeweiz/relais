# P0: Relais Project Scaffold

**Date:** 2026-03-27
**Status:** Approved

## Goal

Set up the Relais mono-repo with Flutter client project and Rust server crate structure. No feature code — just the skeleton that P1/P2 will build on.

## Mono-repo Structure

```
relais/
├── client/                        # Flutter client
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app.dart               # MaterialApp + M3 theme + GoRouter
│   │   ├── models/
│   │   ├── services/
│   │   ├── providers/
│   │   ├── screens/
│   │   │   └── connect_screen.dart  # Placeholder: server URL input
│   │   ├── widgets/
│   │   └── theme/
│   │       └── app_theme.dart     # M3 seed color, dark/light
│   ├── pubspec.yaml
│   ├── analysis_options.yaml
│   └── README.md
├── server/                        # Rust server (migrated from RTB)
│   ├── Cargo.toml                 # Workspace root
│   ├── crates/
│   │   ├── cli/                   # relais CLI entry point
│   │   ├── core/                  # Core: event bus, PTY, sessions, agents, task pool
│   │   ├── server/                # Axum HTTP/WS server, REST API
│   │   └── plugin-host/           # Plugin manager, IM bridge, tunnel bridge
│   └── plugins/
│       ├── feishu-plugin/         # Feishu IM (standalone binary)
│       └── cloudflare-tunnel/     # Cloudflare tunnel (standalone binary)
├── protocol/
│   └── api.md                     # REST + WebSocket protocol spec
├── docs/
│   └── specs/                     # Design specs
├── Makefile
├── README.md
└── .gitignore
```

## Flutter Client Setup

**Project name:** `relais`
**Min SDK:** Flutter 3.24+ (Dart 3.5+)
**Platforms:** iOS, Android, macOS, Windows, Web

### pubspec.yaml dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  # State management
  flutter_riverpod: ^2.6.0
  riverpod_annotation: ^2.6.0
  # Routing
  go_router: ^14.0.0
  # HTTP + WebSocket
  dio: ^5.7.0
  web_socket_channel: ^3.0.0
  # Terminal
  xterm: ^4.0.0
  # UI
  flutter_markdown: ^0.7.0
  # Storage
  shared_preferences: ^2.3.0
  # QR
  mobile_scanner: ^6.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  riverpod_generator: ^2.6.0
  build_runner: ^2.4.0
```

### M3 Theme (app_theme.dart)

```dart
// Seed color for Material 3 dynamic theming
static const seedColor = Color(0xFF6750A4); // Deep purple

ThemeData light = ThemeData(
  useMaterial3: true,
  colorSchemeSeed: seedColor,
  brightness: Brightness.light,
);

ThemeData dark = ThemeData(
  useMaterial3: true,
  colorSchemeSeed: seedColor,
  brightness: Brightness.dark,
);
```

### Scaffold Screens

Only `ConnectScreen` as a placeholder with a text field for server URL and a "Connect" button. This proves the Flutter project builds and runs on all platforms.

## Rust Server Setup

Restructure from the current RTB codebase:

### Renames

| Current | New |
|---------|-----|
| `rtb-cli` (crate name) | `relais-cli` |
| `rtb-core` | `relais-core` |
| `rtb-server` | `relais-server` |
| `rtb-plugin-host` | `relais-plugin-host` |
| `rtb-desktop` (Tauri) | **Remove** (Flutter replaces it) |
| Binary name `rtb` | `relais` |
| Config dir `~/.rtb/` | `~/.relais/` |
| PID file `~/.rtb/rtb.pid` | `~/.relais/relais.pid` |
| Plugins dir `~/.rtb/plugins/` | `~/.relais/plugins/` |
| Config file `~/.rtb/config.toml` | `~/.relais/config.toml` |
| Token file `~/.rtb/token` | `~/.relais/token` |

### Removals

| Remove | Reason |
|--------|--------|
| `crates/tauri-app/` | Flutter replaces Tauri desktop |
| `web/` | Flutter replaces React frontend |
| Notification engine (`crates/core/src/notification/`) | IM bridge replaces it |
| Static file embedding in server | Client is separate |

### What Stays (migrated)

- `crates/core/` → PTY/tmux, sessions, agents, task pool, event bus, config
- `crates/server/` → REST API, WebSocket handlers
- `crates/plugin-host/` → Plugin manager, IM bridge, tunnel bridge
- `crates/cli/` → CLI commands (start, stop, status)
- `plugins/feishu-plugin/` → Feishu WebSocket long connection
- `plugins/cloudflare-tunnel/` → Cloudflare tunnel

## Makefile

```makefile
# Client
client-dev:       # Run Flutter client in debug mode
client-build-ios: # Build iOS
client-build-apk: # Build Android APK
client-build-mac: # Build macOS
client-build-web: # Build web

# Server
server-dev:       # cargo run server in dev mode
server-build:     # cargo build --release
server-install:   # Install relais binary

# Plugins
plugins:          # Build all plugins
install-plugins:  # Install to ~/.relais/plugins/

# All
dev:              # server-dev + client-dev (parallel)
```

## Deliverables

After P0 is complete:
1. `flutter run` works on at least one platform (macOS or Web) showing ConnectScreen
2. `cargo run -p relais-cli -- start` starts the server
3. Mono-repo compiles end to end
4. Old RTB code migrated with renames, Tauri/React/notification engine removed
