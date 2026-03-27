# Relais

Remote terminal access and AI agent interaction — from anywhere.

## Architecture

- **client/** — Flutter app (iOS, Android, macOS, Windows, Web)
- **server/** — Rust backend (terminal, agents, plugins)
- **protocol/** — Shared API specification

## Quick Start

### Server

```bash
make server-dev      # Start server in dev mode
```

### Client

```bash
make client-dev      # Run Flutter client (macOS)
make client-web      # Run Flutter client (Chrome)
```

### Commands

```bash
make help            # Show all targets
```

## License

MIT
