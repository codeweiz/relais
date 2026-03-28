//! Agent Manager — manages multiple ACP-backed agent sessions.
//!
//! Provides a centralized interface for creating, managing, and communicating
//! with agent subprocesses across multiple sessions.  Uses `AcpBackend` as the
//! single execution backend for all agent kinds.

use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use chrono::{DateTime, Utc};
use dashmap::DashMap;
use tracing::{info, warn};

use crate::event_bus::EventBus;
use crate::events::{AgentStatus, ControlEvent, DataEvent, ErrorClass, SessionId};

use super::acp_backend::AcpBackend;
use super::event::{AgentEvent, AgentKind};
use super::status_registry::{AgentActivity, AgentStatusRegistry};

/// Maximum number of automatic restarts before giving up.
/// Used by the event router when detecting agent crashes (Issue #2 auto-restart).
#[allow(dead_code)]
const MAX_RESTART_COUNT: u32 = 3;

/// Tracks state for a managed agent session.
struct ManagedAgent {
    backend: AcpBackend,
    /// Human-readable session name.
    name: String,
    /// The kind of agent (Claude, Gemini, etc.).
    /// Retained for future auto-restart.
    #[allow(dead_code)]
    kind: AgentKind,
    /// Working directory the agent was started in.
    /// Retained for future auto-restart.
    #[allow(dead_code)]
    cwd: PathBuf,
    /// When the agent was created.
    created_at: DateTime<Utc>,
    /// How many times this agent has been restarted.
    /// Retained for future auto-restart.
    #[allow(dead_code)]
    restart_count: u32,
    /// Optional companion terminal session for this agent.
    companion_terminal_id: Option<String>,
    /// Persisted event history for replay on reconnect.
    event_history: Arc<Mutex<Vec<AgentEvent>>>,
}

/// Manages the lifecycle of all agent sessions.
pub struct AgentManager {
    /// Active agents keyed by session ID.
    agents: DashMap<SessionId, ManagedAgent>,
    /// Event bus for publishing control/data events.
    event_bus: Arc<EventBus>,
    /// Registry tracking real-time activity status of all agents.
    status_registry: Arc<AgentStatusRegistry>,
    /// Persistent session store for metadata and event history.
    session_store: Arc<crate::session::store::SessionStore>,
}

impl AgentManager {
    /// Create a new agent manager.
    pub fn new(
        event_bus: Arc<EventBus>,
        status_registry: Arc<AgentStatusRegistry>,
        session_store: Arc<crate::session::store::SessionStore>,
    ) -> Self {
        Self {
            agents: DashMap::new(),
            event_bus,
            status_registry,
            session_store,
        }
    }

    /// Create and start a new agent session.
    ///
    /// If the agent binary cannot be spawned or initialization fails, the agent
    /// is still registered in a "crashed" state so the caller can see it in the
    /// session list and understand what went wrong.
    pub async fn create_agent(
        &self,
        session_id: SessionId,
        name: &str,
        provider: &str,
        _model: &str,
        cwd: PathBuf,
    ) -> Result<(), String> {
        self.create_agent_with_resume(session_id, name, provider, _model, cwd, None)
            .await
    }

    /// Create and start a new agent session, optionally resuming a previous CLI session.
    ///
    /// When `resume_session_id` is `Some`, the underlying CLI agent is started
    /// with `--resume <id>` so it picks up its prior conversation context.
    pub async fn create_agent_with_resume(
        &self,
        session_id: SessionId,
        name: &str,
        provider: &str,
        _model: &str,
        cwd: PathBuf,
        resume_session_id: Option<&str>,
    ) -> Result<(), String> {
        info!(
            session_id = %session_id,
            name = %name,
            provider = %provider,
            cwd = %cwd.display(),
            resume_session_id = ?resume_session_id,
            "creating agent"
        );

        let kind = parse_agent_kind(provider);
        let mut backend = AcpBackend::new(kind.clone());
        let created_at = Utc::now();

        // Subscribe to the broadcast channel BEFORE starting the backend so that
        // any events emitted during initialization (e.g. AvailableCommands from the
        // initialize control_response) are captured by the event router.
        let event_history: Arc<Mutex<Vec<AgentEvent>>> = Arc::new(Mutex::new(Vec::new()));
        self.start_event_router(session_id.clone(), &backend, event_history.clone());

        let cwd_str = cwd.display().to_string();

        // Attempt to start the backend. On failure, register in crashed state.
        match backend.start(&cwd, resume_session_id).await {
            Ok(()) => {
                let managed = ManagedAgent {
                    backend,
                    name: name.to_string(),
                    kind,
                    cwd,
                    created_at,
                    restart_count: 0,
                    companion_terminal_id: None,
                    event_history,
                };

                self.agents.insert(session_id.clone(), managed);
                self.status_registry.register(&session_id, name, provider);

                // Persist session metadata to disk for restore on restart.
                let meta = crate::session::types::SessionMeta {
                    id: session_id.clone(),
                    name: name.to_string(),
                    session_type: crate::session::types::SessionType::Agent,
                    agent: Some(crate::session::types::AgentInfo {
                        provider: provider.to_string(),
                        model: String::new(),
                    }),
                    shell: None,
                    cwd: cwd_str.clone(),
                    created_at,
                    last_active: created_at,
                    last_seq: 0,
                    status: crate::session::types::SessionStatus::Running,
                    parent_id: None,
                    tags: Vec::new(),
                    acp_session_id: None,
                };
                if let Err(e) = self.session_store.create(&meta) {
                    warn!(session_id = %session_id, error = %e, "failed to persist session metadata");
                }

                // Publish session creation + ready events so clients discover
                // the new agent immediately.
                self.event_bus
                    .publish_control(ControlEvent::SessionCreated {
                        session_id: session_id.clone(),
                        session_type: crate::events::SessionType::Agent,
                    });
                self.event_bus
                    .publish_control(ControlEvent::AgentStatusChanged {
                        session_id,
                        status: AgentStatus::Ready,
                    });

                Ok(())
            }
            Err(e) => {
                warn!(
                    session_id = %session_id,
                    error = %e,
                    "agent failed to start, registering in crashed state"
                );

                let managed = ManagedAgent {
                    backend,
                    name: name.to_string(),
                    kind,
                    cwd,
                    created_at,
                    restart_count: 0,
                    companion_terminal_id: None,
                    // Reuse the already-subscribed event_history so the router
                    // drains cleanly even when the agent fails to start.
                    event_history,
                };

                self.agents.insert(session_id.clone(), managed);
                self.status_registry.register(&session_id, name, provider);

                self.event_bus
                    .publish_control(ControlEvent::AgentStatusChanged {
                        session_id: session_id.clone(),
                        status: AgentStatus::Crashed {
                            error: e.clone(),
                            class: ErrorClass::Permanent,
                        },
                    });

                Err(e)
            }
        }
    }

    /// Send a message to an agent (fire-and-forget).
    ///
    /// The caller uses the event stream to detect when the turn finishes.
    pub async fn send_message(&self, session_id: &str, text: String) -> Result<(), String> {
        self.send_message_from(session_id, text, "web").await
    }

    /// Send a user message to an agent, with source tracking.
    ///
    /// Publishes an `AgentUserMessage` data event so all subscribers (web UI,
    /// IM bridge) can see the user's input regardless of origin.
    pub async fn send_message_from(
        &self,
        session_id: &str,
        text: String,
        source: &str,
    ) -> Result<(), String> {
        let agent = self
            .agents
            .get(session_id)
            .ok_or_else(|| "Agent not running".to_string())?;

        // Store user message in event history for replay on reconnect
        if let Some(entry) = self.agents.get(session_id) {
            if let Ok(mut history) = entry.event_history.lock() {
                history.push(crate::agent::event::AgentEvent::UserMessage {
                    text: text.clone(),
                    source: source.to_string(),
                });
            }
        }

        // Publish user message event so all frontends can see it
        self.event_bus
            .publish_data(
                session_id,
                crate::events::DataEvent::AgentUserMessage {
                    seq: 0,
                    text: text.clone(),
                    source: source.to_string(),
                },
            )
            .await;

        // Slash commands: write directly to stdin so the CLI handles them
        if text.starts_with('/') {
            return agent.backend.write_stdin(&format!("{}\n", text)).await;
        }

        agent.backend.send_message_fire(&text).await
    }

    /// Kill an agent session.
    pub async fn kill_agent(&self, session_id: &str) -> Result<(), String> {
        if let Some(mut entry) = self.agents.get_mut(session_id) {
            entry.value_mut().backend.shutdown().await;
            drop(entry);
            self.status_registry.unregister(session_id);
            self.agents.remove(session_id);
            info!(session_id = %session_id, "agent killed");
            Ok(())
        } else {
            Err("Agent not running".to_string())
        }
    }

    /// List all active agent sessions with metadata.
    pub fn list_agents(&self) -> Vec<(SessionId, String, AgentStatus, DateTime<Utc>)> {
        self.agents
            .iter()
            .map(|entry| {
                let m = entry.value();
                (
                    entry.key().clone(),
                    m.name.clone(),
                    AgentStatus::Ready, // Simplified: actual status tracked via events
                    m.created_at,
                )
            })
            .collect()
    }

    /// Set the companion terminal for an agent.
    pub fn set_companion_terminal(
        &self,
        agent_session_id: &str,
        terminal_id: &str,
    ) -> Result<(), String> {
        let mut entry = self
            .agents
            .get_mut(agent_session_id)
            .ok_or_else(|| format!("agent not found: {}", agent_session_id))?;
        entry.companion_terminal_id = Some(terminal_id.to_string());
        Ok(())
    }

    /// Get the companion terminal ID for an agent.
    pub fn get_companion_terminal(&self, agent_session_id: &str) -> Option<String> {
        self.agents
            .get(agent_session_id)
            .and_then(|entry| entry.companion_terminal_id.clone())
    }

    /// Find agents that have this terminal as companion.
    pub fn find_agents_for_terminal(&self, terminal_id: &str) -> Vec<String> {
        self.agents
            .iter()
            .filter(|entry| entry.companion_terminal_id.as_deref() == Some(terminal_id))
            .map(|entry| entry.key().clone())
            .collect()
    }

    /// Retrieve the full event history for a session (used for replay on reconnect).
    pub fn get_event_history(&self, session_id: &str) -> Vec<AgentEvent> {
        self.agents
            .get(session_id)
            .map(|entry| entry.event_history.lock().unwrap().clone())
            .unwrap_or_default()
    }

    /// Find a running agent's session ID by name.
    pub fn find_agent_by_name(&self, name: &str) -> Option<String> {
        self.agents
            .iter()
            .find(|entry| entry.value().name == name)
            .map(|entry| entry.key().clone())
    }

    /// Check if an agent session exists.
    pub fn has_agent(&self, session_id: &str) -> bool {
        self.agents.contains_key(session_id)
    }

    /// Get the number of active agents.
    pub fn agent_count(&self) -> usize {
        self.agents.len()
    }

    /// Start routing events from the AcpBackend's broadcast channel to the EventBus.
    /// Also persists events into `event_history` for replay on WebSocket reconnect.
    fn start_event_router(
        &self,
        session_id: String,
        backend: &AcpBackend,
        event_history: Arc<Mutex<Vec<AgentEvent>>>,
    ) {
        let mut rx = backend.subscribe();
        let event_bus = self.event_bus.clone();
        let status_registry = self.status_registry.clone();
        let event_bus_for_status = self.event_bus.clone();
        let session_store = self.session_store.clone();
        let sid = session_id.clone();
        let mut seq: u64 = 1;

        tokio::spawn(async move {
            loop {
                match rx.recv().await {
                    Ok(event) => {
                        // AvailableCommands: store in history (replace any previous entry)
                        // so reconnecting clients always receive the latest slash commands.
                        // Do NOT increment seq — it's metadata, not a conversational event.
                        let is_available_commands =
                            matches!(event, AgentEvent::AvailableCommands(_));
                        if is_available_commands {
                            if let Ok(mut history) = event_history.lock() {
                                // Remove any stale AvailableCommands entry and add the fresh one.
                                history
                                    .retain(|e| !matches!(e, AgentEvent::AvailableCommands(_)));
                                history.push(event.clone());
                            }
                        } else {
                            if let Ok(mut history) = event_history.lock() {
                                history.push(event.clone());
                            }
                            seq += 1;
                        }

                        let data_event = agent_event_to_data_event(seq, &event);
                        event_bus.publish_data(&sid, data_event).await;

                        // Persist event to disk for session history recovery.
                        if !is_available_commands {
                            let evt_type = match &event {
                                AgentEvent::Text(_) => "text",
                                AgentEvent::Thinking(_) => "thinking",
                                AgentEvent::ToolUse { .. } => "tool_use",
                                AgentEvent::ToolResult { .. } => "tool_result",
                                AgentEvent::TurnComplete { .. } => "turn_complete",
                                AgentEvent::Error(_) => "error",
                                AgentEvent::UserMessage { .. } => "user_message",
                                AgentEvent::Progress(_) => "progress",
                                AgentEvent::AvailableCommands(_) => "available_commands",
                            };
                            let data = match &event {
                                AgentEvent::Text(c) => serde_json::json!({"content": c}),
                                AgentEvent::Thinking(c) => serde_json::json!({"content": c}),
                                AgentEvent::ToolUse { id, name, input } => serde_json::json!({"id": id, "name": name, "input": input}),
                                AgentEvent::ToolResult { id, output, is_error } => serde_json::json!({"id": id, "output": output, "is_error": is_error}),
                                AgentEvent::TurnComplete { cost_usd, .. } => serde_json::json!({"cost_usd": cost_usd}),
                                AgentEvent::Error(msg) => serde_json::json!({"message": msg}),
                                AgentEvent::UserMessage { text, source } => serde_json::json!({"text": text, "source": source}),
                                AgentEvent::Progress(msg) => serde_json::json!({"message": msg}),
                                AgentEvent::AvailableCommands(_) => serde_json::Value::Null,
                            };
                            let session_event = crate::session::types::SessionEvent {
                                seq,
                                event_type: evt_type.to_string(),
                                ts: chrono::Utc::now().timestamp_millis(),
                                data,
                            };
                            if let Err(e) = session_store.append_event(&sid, &session_event) {
                                warn!(session_id = %sid, error = %e, "failed to persist agent event");
                            }
                        }

                        // Update status registry and broadcast activity change
                        let (activity_status, activity_text, event_cost) = match &event {
                            AgentEvent::Text(content) => {
                                let summary: String = content.chars().take(100).collect();
                                (AgentActivity::Working, summary, None)
                            }
                            AgentEvent::Thinking(_) => {
                                (AgentActivity::Thinking, "Thinking...".to_string(), None)
                            }
                            AgentEvent::ToolUse { name, .. } => {
                                (AgentActivity::ToolCalling, format!("Using: {}", name), None)
                            }
                            AgentEvent::ToolResult { .. } => {
                                (AgentActivity::Working, "Processing result...".to_string(), None)
                            }
                            AgentEvent::TurnComplete { session_id, cost_usd } => {
                                // Persist the CLI session ID to meta.json so we
                                // can resume this agent session later.
                                if let Some(ref cli_sid) = session_id {
                                    if let Ok(mut meta) = session_store.get_meta(&sid) {
                                        if meta.acp_session_id.as_deref() != Some(cli_sid.as_str()) {
                                            meta.acp_session_id = Some(cli_sid.clone());
                                            let _ = session_store.update_meta(&sid, &meta);
                                        }
                                    }
                                }
                                (AgentActivity::Idle, String::new(), *cost_usd)
                            }
                            AgentEvent::Error(msg) => {
                                let summary: String = msg.chars().take(80).collect();
                                (AgentActivity::Error, summary, None)
                            }
                            AgentEvent::UserMessage { .. } => {
                                (AgentActivity::Working, "Processing message...".to_string(), None)
                            }
                            AgentEvent::AvailableCommands(_) | AgentEvent::Progress(_) => {
                                (AgentActivity::Working, String::new(), None)
                            }
                        };

                        let changed = status_registry.update(
                            &sid,
                            activity_status.clone(),
                            &activity_text,
                            event_cost,
                        );
                        if changed {
                            event_bus_for_status.publish_control(
                                ControlEvent::AgentActivityChanged {
                                    session_id: sid.clone(),
                                    status: activity_status.to_string(),
                                    activity: activity_text,
                                },
                            );
                        }
                    }
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                        warn!(session_id = %sid, skipped = n, "event router lagged, some events lost");
                        continue;
                    }
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                        // Agent broadcast channel closed — agent process died
                        info!(session_id = %sid, "agent event channel closed");
                        break;
                    }
                }
            }
        });
    }

    /// Shut down all agents.
    pub async fn shutdown_all(&self) {
        let keys: Vec<SessionId> = self.agents.iter().map(|e| e.key().clone()).collect();
        for session_id in keys {
            if let Some(mut entry) = self.agents.get_mut(&session_id) {
                entry.value_mut().backend.shutdown().await;
            }
            self.agents.remove(&session_id);
        }
        info!("all agents shut down");
    }
}

/// Parse a provider string into an AgentKind.
fn parse_agent_kind(provider: &str) -> AgentKind {
    match provider {
        "claude" | "claude-code" => AgentKind::Claude,
        "gemini" | "gemini-cli" => AgentKind::Gemini,
        "opencode" => AgentKind::OpenCode,
        "codex" => AgentKind::Codex,
        // Default to Claude for unknown providers
        _ => AgentKind::Claude,
    }
}

/// Convert an `AgentEvent` to a `DataEvent` with the given sequence number.
/// Shared between live event routing and history replay.
pub fn agent_event_to_data_event(seq: u64, event: &AgentEvent) -> DataEvent {
    match event {
        AgentEvent::Text(content) => DataEvent::AgentText {
            seq,
            content: content.clone(),
            streaming: true,
        },
        AgentEvent::Thinking(content) => DataEvent::AgentThinking {
            seq,
            content: content.clone(),
        },
        AgentEvent::ToolUse { name, id, input } => DataEvent::AgentToolUse {
            seq,
            id: id.clone(),
            name: name.clone(),
            input: serde_json::Value::String(input.clone().unwrap_or_default()),
        },
        AgentEvent::ToolResult {
            id,
            output,
            is_error,
        } => DataEvent::AgentToolResult {
            seq,
            id: id.clone(),
            output: output.clone().unwrap_or_default(),
            is_error: *is_error,
        },
        AgentEvent::Progress(message) => DataEvent::AgentProgress {
            seq,
            message: message.clone(),
        },
        AgentEvent::TurnComplete { cost_usd, .. } => DataEvent::AgentTurnComplete {
            seq,
            cost_usd: *cost_usd,
        },
        AgentEvent::Error(message) => DataEvent::AgentError {
            seq,
            message: message.clone(),
            severity: ErrorClass::Transient,
            guidance: String::new(),
        },
        AgentEvent::UserMessage { text, source } => DataEvent::AgentUserMessage {
            seq,
            text: text.clone(),
            source: source.clone(),
        },
        AgentEvent::AvailableCommands(cmds) => DataEvent::AgentAvailableCommands {
            commands: cmds
                .iter()
                .map(|c| (c.name.clone(), c.description.clone()))
                .collect(),
        },
    }
}
