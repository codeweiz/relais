# P0: Relais Project Scaffold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set up the Relais mono-repo with a working Flutter client skeleton and a migrated Rust server, proving both compile and run.

**Architecture:** Mono-repo with `client/` (Flutter) and `server/` (Rust workspace). The Rust code is migrated from the existing RTB project at `/Users/zhouwei/Projects/ai/remote-desktop-control` with full rename (RTB → Relais). Flutter client is created fresh with Material 3 theming and a placeholder ConnectScreen.

**Tech Stack:** Flutter 3.24+, Dart 3.5+, Rust 1.94, Cargo workspace

**Spec:** `docs/specs/2026-03-27-p0-project-scaffold-design.md`

---

### Task 1: Install Flutter SDK

**Files:** None (system setup)

- [ ] **Step 1: Install Flutter via Homebrew**

```bash
brew install --cask flutter
```

- [ ] **Step 2: Verify installation**

Run: `flutter --version`
Expected: Flutter 3.24+ with Dart 3.5+

- [ ] **Step 3: Run Flutter doctor**

Run: `flutter doctor`
Expected: Shows available platforms (macOS, Web, iOS). Fix any critical issues.

- [ ] **Step 4: Enable desktop and web**

```bash
flutter config --enable-macos-desktop
flutter config --enable-web
```

---

### Task 2: Create mono-repo directory structure

**Files:**
- Create: `Makefile`
- Create: `.gitignore`
- Create: `README.md`
- Create: `protocol/api.md`

- [ ] **Step 1: Create top-level structure**

```bash
cd /Users/zhouwei/Projects/ai/relais
mkdir -p client server protocol docs/specs docs/plans
```

- [ ] **Step 2: Create root .gitignore**

```gitignore
# Flutter
client/.dart_tool/
client/.packages
client/build/
client/.flutter-plugins
client/.flutter-plugins-dependencies
client/pubspec.lock

# Rust
server/target/
server/plugins/*/target/

# IDE
.idea/
.vscode/
*.iml
.DS_Store

# Config (local secrets)
*.local.toml
```

- [ ] **Step 3: Create root Makefile**

```makefile
.PHONY: dev client-dev server-dev client-build server-build plugins install help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# ── Development ──────────────────────────────────────────
client-dev: ## Run Flutter client (debug, macOS)
	cd client && flutter run -d macos

client-web: ## Run Flutter client (debug, Chrome)
	cd client && flutter run -d chrome

server-dev: install-plugins ## Run Relais server (dev mode)
	cd server && cargo run -p relais-cli -- start

# ── Build ────────────────────────────────────────────────
client-build-web: ## Build Flutter web client
	cd client && flutter build web

server-build: ## Build Relais server (release)
	cd server && cargo build --release -p relais-cli

# ── Plugins ──────────────────────────────────────────────
plugins: ## Build all plugins
	cd server && cargo build --manifest-path plugins/feishu-plugin/Cargo.toml
	cd server && cargo build --manifest-path plugins/cloudflare-tunnel/Cargo.toml

install-plugins: plugins ## Install plugins to ~/.relais/plugins/
	@mkdir -p ~/.relais/plugins/feishu-im ~/.relais/plugins/cloudflare-tunnel
	@cp server/plugins/feishu-plugin/target/debug/feishu-plugin ~/.relais/plugins/feishu-im/
	@test -f ~/.relais/plugins/feishu-im/plugin.toml || cp server/plugins/feishu-plugin/plugin.toml ~/.relais/plugins/feishu-im/plugin.toml
	@cp server/plugins/cloudflare-tunnel/target/debug/cloudflare-tunnel ~/.relais/plugins/cloudflare-tunnel/
	@test -f ~/.relais/plugins/cloudflare-tunnel/plugin.toml || cp server/plugins/cloudflare-tunnel/plugin.toml ~/.relais/plugins/cloudflare-tunnel/plugin.toml
	@echo "Plugins installed to ~/.relais/plugins/"

# ── Install ──────────────────────────────────────────────
server-install: server-build install-plugins ## Build and install relais to /usr/local/bin
	cp server/target/release/relais-cli /usr/local/bin/relais

# ── Quality ──────────────────────────────────────────────
test: ## Run all tests
	cd server && cargo test --workspace
	cd client && flutter test

clean: ## Remove build artifacts
	cd server && cargo clean
	cd client && flutter clean
```

- [ ] **Step 4: Create root README.md**

```markdown
# Relais

Remote terminal access and AI agent interaction — from anywhere.

## Architecture

- **client/** — Flutter app (iOS, Android, macOS, Windows, Web)
- **server/** — Rust backend (terminal, agents, plugins)
- **protocol/** — Shared API specification

## Quick Start

### Server

\```bash
make server-dev      # Start server in dev mode
\```

### Client

\```bash
make client-dev      # Run Flutter client (macOS)
make client-web      # Run Flutter client (Chrome)
\```

### Commands

\```bash
make help            # Show all targets
\```

## License

MIT
```

- [ ] **Step 5: Create protocol/api.md** (placeholder)

```markdown
# Relais Protocol

REST API and WebSocket protocol specification.

(To be documented in P1)
```

- [ ] **Step 6: Commit**

```bash
git add .
git commit -m "chore: create mono-repo structure (Makefile, .gitignore, README)"
```

---

### Task 3: Create Flutter client project

**Files:**
- Create: `client/` (entire Flutter project via `flutter create`)
- Modify: `client/pubspec.yaml`
- Create: `client/lib/app.dart`
- Create: `client/lib/theme/app_theme.dart`
- Create: `client/lib/screens/connect_screen.dart`
- Modify: `client/lib/main.dart`

- [ ] **Step 1: Create Flutter project**

```bash
cd /Users/zhouwei/Projects/ai/relais
flutter create --project-name relais --org com.relais --platforms ios,android,macos,windows,web client
```

- [ ] **Step 2: Update pubspec.yaml dependencies**

Replace `client/pubspec.yaml` with the dependencies from the spec:
- flutter_riverpod, riverpod_annotation
- go_router
- dio, web_socket_channel
- xterm
- flutter_markdown
- shared_preferences
- mobile_scanner

Run: `cd client && flutter pub get`
Expected: Dependencies resolved successfully.

- [ ] **Step 3: Create M3 theme**

Create `client/lib/theme/app_theme.dart`:

```dart
import 'package:flutter/material.dart';

class AppTheme {
  static const seedColor = Color(0xFF6750A4);

  static ThemeData light() => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: seedColor,
    brightness: Brightness.light,
  );

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: seedColor,
    brightness: Brightness.dark,
  );
}
```

- [ ] **Step 4: Create ConnectScreen placeholder**

Create `client/lib/screens/connect_screen.dart`:

```dart
import 'package:flutter/material.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.terminal_rounded,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Relais',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Connect to a server',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'https://your-server.example.com',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _tokenController,
                  decoration: const InputDecoration(
                    labelText: 'Token',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.key_outlined),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    // TODO: P1 - connect to server
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Connection not yet implemented')),
                    );
                  },
                  icon: const Icon(Icons.link),
                  label: const Text('Connect'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Create app.dart with GoRouter**

Create `client/lib/app.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'theme/app_theme.dart';
import 'screens/connect_screen.dart';

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const ConnectScreen(),
    ),
  ],
);

class RelaisApp extends StatelessWidget {
  const RelaisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Relais',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}
```

- [ ] **Step 6: Update main.dart**

Replace `client/lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'app.dart';

void main() {
  runApp(const RelaisApp());
}
```

- [ ] **Step 7: Verify Flutter client runs**

Run: `cd client && flutter run -d macos` (or `flutter run -d chrome` if macOS desktop not available)
Expected: App launches showing "Relais" title, server URL field, token field, Connect button with Material 3 styling.

- [ ] **Step 8: Commit**

```bash
git add client/
git commit -m "feat(client): initialize Flutter project with M3 theme and ConnectScreen"
```

---

### Task 4: Migrate Rust server from RTB

**Source:** `/Users/zhouwei/Projects/ai/remote-desktop-control`
**Destination:** `/Users/zhouwei/Projects/ai/relais/server/`

- [ ] **Step 1: Copy Rust source code**

```bash
RELAIS=/Users/zhouwei/Projects/ai/relais/server
RTB=/Users/zhouwei/Projects/ai/remote-desktop-control

# Copy workspace
cp $RTB/Cargo.toml $RELAIS/Cargo.toml
cp $RTB/Cargo.lock $RELAIS/Cargo.lock

# Copy crates (excluding tauri-app)
mkdir -p $RELAIS/crates
cp -r $RTB/crates/core $RELAIS/crates/core
cp -r $RTB/crates/server $RELAIS/crates/server
cp -r $RTB/crates/plugin-host $RELAIS/crates/plugin-host
cp -r $RTB/crates/cli $RELAIS/crates/cli

# Copy plugins
cp -r $RTB/plugins $RELAIS/plugins
```

- [ ] **Step 2: Update workspace Cargo.toml**

Remove `tauri-app` from workspace members, remove any `web/` references. Update workspace member paths. The workspace Cargo.toml should list:

```toml
[workspace]
members = [
    "crates/core",
    "crates/server",
    "crates/plugin-host",
    "crates/cli",
]
resolver = "2"

[workspace.package]
version = "0.1.0"
edition = "2021"
license = "MIT"
```

- [ ] **Step 3: Rename crate packages (rtb → relais)**

In each `crates/*/Cargo.toml`:
- `crates/cli/Cargo.toml`: name = `"relais-cli"`, binary name = `"relais"`
- `crates/core/Cargo.toml`: name = `"relais-core"`
- `crates/server/Cargo.toml`: name = `"relais-server"`
- `crates/plugin-host/Cargo.toml`: name = `"relais-plugin-host"`

Update all inter-crate dependency references:
- `rtb-core` → `relais-core`
- `rtb-server` → `relais-server`
- `rtb-plugin-host` → `relais-plugin-host`

Update all `use rtb_core::` → `use relais_core::` etc. in source files.
Update all `use rtb_server::` → `use relais_server::` etc.

- [ ] **Step 4: Rename paths and strings (RTB → Relais)**

Search and replace across all `.rs` files:
- `~/.rtb/` → `~/.relais/`
- `rtb.pid` → `relais.pid`
- `RTB 2.0` → `Relais`
- `rtb` (in user-facing strings) → `relais`
- Config dir references

Key files:
- `crates/core/src/config.rs` — default paths
- `crates/cli/src/commands/start.rs` — banner, PID file
- `crates/cli/src/commands/daemon.rs` — PID file path
- `crates/cli/src/main.rs` — clap app name

- [ ] **Step 5: Remove Tauri and notification engine**

- Delete any references to `tauri-app` in workspace Cargo.toml
- Remove `crates/core/src/notification/` directory
- Remove notification-related code from `CoreState` (notification_router, notification_store fields)
- Remove notification event handling from CLI start command
- Remove notification imports and references from server code
- Remove the web/ static file embedding from `crates/server/` (if any)

- [ ] **Step 6: Verify server compiles**

Run: `cd /Users/zhouwei/Projects/ai/relais/server && cargo check`
Expected: Compiles with no errors (warnings OK).

- [ ] **Step 7: Verify server runs**

Run: `cd /Users/zhouwei/Projects/ai/relais/server && cargo run -p relais-cli -- start`
Expected: Server starts, shows "Relais is running!" banner.

- [ ] **Step 8: Commit**

```bash
git add server/
git commit -m "feat(server): migrate Rust server from RTB, rename to Relais"
```

---

### Task 5: Verify end-to-end and finalize

**Files:**
- Modify: `Makefile` (verify targets work)

- [ ] **Step 1: Test make server-dev**

Run: `make server-dev`
Expected: Plugins build, server starts.

- [ ] **Step 2: Test make client-dev (in another terminal)**

Run: `make client-dev`
Expected: Flutter app launches with ConnectScreen.

- [ ] **Step 3: Test make test**

Run: `make test`
Expected: Rust tests pass (some may need fixing after rename). Flutter tests pass.

- [ ] **Step 4: Test make clean**

Run: `make clean`
Expected: Build artifacts removed.

- [ ] **Step 5: Final commit**

```bash
git add .
git commit -m "chore: verify end-to-end build (server + client)"
```
