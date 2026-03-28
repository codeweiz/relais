//! Agent Status Registry — aggregated real-time status for all agents.

use std::time::Instant;

use dashmap::DashMap;
use serde::Serialize;

/// Activity state of an agent.
#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum AgentActivity {
    Idle,
    Working,
    Thinking,
    ToolCalling,
    Error,
}

impl std::fmt::Display for AgentActivity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AgentActivity::Idle => write!(f, "idle"),
            AgentActivity::Working => write!(f, "working"),
            AgentActivity::Thinking => write!(f, "thinking"),
            AgentActivity::ToolCalling => write!(f, "tool_calling"),
            AgentActivity::Error => write!(f, "error"),
        }
    }
}

/// Aggregated status for a single agent.
#[derive(Debug, Clone)]
pub struct AgentStatusEntry {
    pub session_id: String,
    pub name: String,
    pub provider: String,
    pub status: AgentActivity,
    pub activity: String,
    pub cost_usd: Option<f64>,
    pub updated_at: Instant,
}

/// JSON-serializable snapshot of agent status (for REST API).
#[derive(Debug, Serialize)]
pub struct AgentStatusSnapshot {
    pub session_id: String,
    pub name: String,
    pub provider: String,
    pub status: AgentActivity,
    pub activity: String,
    pub cost_usd: Option<f64>,
}

impl From<&AgentStatusEntry> for AgentStatusSnapshot {
    fn from(entry: &AgentStatusEntry) -> Self {
        Self {
            session_id: entry.session_id.clone(),
            name: entry.name.clone(),
            provider: entry.provider.clone(),
            status: entry.status.clone(),
            activity: entry.activity.clone(),
            cost_usd: entry.cost_usd,
        }
    }
}

/// Thread-safe registry of all agent statuses.
pub struct AgentStatusRegistry {
    entries: DashMap<String, AgentStatusEntry>,
}

impl AgentStatusRegistry {
    pub fn new() -> Self {
        Self {
            entries: DashMap::new(),
        }
    }

    /// Register a new agent.
    pub fn register(&self, session_id: &str, name: &str, provider: &str) {
        self.entries.insert(
            session_id.to_string(),
            AgentStatusEntry {
                session_id: session_id.to_string(),
                name: name.to_string(),
                provider: provider.to_string(),
                status: AgentActivity::Idle,
                activity: String::new(),
                cost_usd: None,
                updated_at: Instant::now(),
            },
        );
    }

    /// Remove an agent.
    pub fn unregister(&self, session_id: &str) {
        self.entries.remove(session_id);
    }

    /// Update activity. Returns true if the status actually changed (for throttling).
    pub fn update(
        &self,
        session_id: &str,
        status: AgentActivity,
        activity: &str,
        cost_usd: Option<f64>,
    ) -> bool {
        if let Some(mut entry) = self.entries.get_mut(session_id) {
            let changed = entry.status != status || entry.activity != activity;
            entry.status = status;
            entry.activity = activity.to_string();
            if let Some(cost) = cost_usd {
                entry.cost_usd = Some(entry.cost_usd.unwrap_or(0.0) + cost);
            }
            entry.updated_at = Instant::now();
            changed
        } else {
            false
        }
    }

    /// Get a snapshot of all agents for the REST API.
    pub fn snapshot(&self) -> Vec<AgentStatusSnapshot> {
        self.entries
            .iter()
            .map(|e| AgentStatusSnapshot::from(e.value()))
            .collect()
    }
}
