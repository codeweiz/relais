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
