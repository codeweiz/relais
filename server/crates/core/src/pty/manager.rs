use std::sync::Arc;

use anyhow::{anyhow, Result};
use dashmap::DashMap;
use tracing::{debug, info};

use crate::config::Config;
use crate::event_bus::EventBus;
use crate::events::{ControlEvent, SessionType};

use super::session::{PtySession, PtySessionInfo};
use super::tmux;

/// Manages multiple PTY sessions.
///
/// Provides CRUD operations for terminal sessions, delegating the actual
/// PTY handling to `PtySession`. Publishes lifecycle events
/// (`SessionCreated`, `SessionDeleted`) to the EventBus.
pub struct PtyManager {
    sessions: DashMap<String, Arc<PtySession>>,
    event_bus: Arc<EventBus>,
    config: Arc<Config>,
    session_store: Arc<crate::session::store::SessionStore>,
}

impl PtyManager {
    /// Create a new PTY manager.
    pub fn new(
        event_bus: Arc<EventBus>,
        config: Arc<Config>,
        session_store: Arc<crate::session::store::SessionStore>,
    ) -> Self {
        Self {
            sessions: DashMap::new(),
            event_bus,
            config,
            session_store,
        }
    }

    /// Create a new PTY session.
    ///
    /// Spawns a tmux-backed PTY with an optional working directory,
    /// starts a background output reader, and publishes a
    /// `ControlEvent::SessionCreated` event.
    ///
    /// Returns the generated session ID.
    pub async fn create_session(
        &self,
        name: &str,
        cwd: Option<&std::path::Path>,
    ) -> Result<String> {
        let id_length = self.config.session.session_id_length;
        let session_id = nanoid::nanoid!(id_length);

        let session = PtySession::spawn(session_id.clone(), name.to_string(), cwd)?;

        self.sessions.insert(session_id.clone(), session);

        info!(session_id = %session_id, name = %name, "created PTY session");

        // Persist session metadata to disk.
        let now = chrono::Utc::now();
        let meta = crate::session::types::SessionMeta {
            id: session_id.clone(),
            name: name.to_string(),
            session_type: crate::session::types::SessionType::Terminal,
            agent: None,
            shell: Some(self.config.server.shell.clone()),
            cwd: cwd
                .map(|p| p.display().to_string())
                .unwrap_or_else(|| ".".to_string()),
            created_at: now,
            last_active: now,
            last_seq: 0,
            status: crate::session::types::SessionStatus::Running,
            parent_id: None,
            tags: Vec::new(),
            acp_session_id: None,
        };
        if let Err(e) = self.session_store.create(&meta) {
            tracing::warn!(session_id = %session_id, error = %e, "failed to persist terminal session metadata");
        }

        self.event_bus
            .publish_control(ControlEvent::SessionCreated {
                session_id: session_id.clone(),
                session_type: SessionType::Terminal,
            });

        Ok(session_id)
    }

    /// Get a session by ID.
    pub fn get_session(&self, id: &str) -> Option<Arc<PtySession>> {
        self.sessions.get(id).map(|entry| entry.value().clone())
    }

    /// List all active sessions as lightweight info structs.
    pub fn list_sessions(&self) -> Vec<PtySessionInfo> {
        self.sessions
            .iter()
            .map(|entry| entry.value().info())
            .collect()
    }

    /// Write input data to the stdin of the specified session.
    pub fn write_input(&self, id: &str, data: &[u8]) -> Result<()> {
        let session = self
            .sessions
            .get(id)
            .ok_or_else(|| anyhow!("session not found: {}", id))?;
        session.write_input(data)
    }

    /// Resize the terminal of the specified session.
    pub fn resize(&self, id: &str, cols: u16, rows: u16) -> Result<()> {
        let session = self
            .sessions
            .get(id)
            .ok_or_else(|| anyhow!("session not found: {}", id))?;
        session.resize(cols, rows)?;
        debug!(session_id = %id, cols, rows, "resized PTY session");
        Ok(())
    }

    /// Kill a session and remove it from management.
    ///
    /// Kills the child process, removes the session from the internal map,
    /// publishes a `ControlEvent::SessionDeleted` event, and cleans up
    /// the EventBus session channels.
    pub async fn kill_session(&self, id: &str) -> Result<()> {
        let (_, session) = self
            .sessions
            .remove(id)
            .ok_or_else(|| anyhow!("session not found: {}", id))?;

        // Kill the child process. Ignore errors if already exited.
        if session.is_running() {
            if let Err(e) = session.kill() {
                debug!(session_id = %id, error = %e, "error killing PTY (may have already exited)");
            }
        }

        info!(session_id = %id, "killed PTY session");

        self.event_bus
            .publish_control(ControlEvent::SessionDeleted {
                session_id: id.to_string(),
            });

        self.event_bus.remove_session(id);

        Ok(())
    }

    /// Return the number of active sessions.
    pub fn session_count(&self) -> usize {
        self.sessions.len()
    }

    /// Kill any orphaned Relais tmux sessions that are not tracked by this manager.
    ///
    /// This is called at startup to clean up tmux sessions left behind by
    /// a previous server instance that crashed or was killed without cleanup.
    pub fn cleanup_orphans(&self) {
        if let Err(e) = tmux::cleanup_orphans() {
            tracing::warn!(error = %e, "failed to cleanup orphan tmux sessions");
        }
    }
}
