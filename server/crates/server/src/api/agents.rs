use axum::{extract::State, Json};

use crate::state::AppState;
use relais_core::agent::status_registry::AgentStatusSnapshot;

/// GET /api/v1/agents/status — returns all agents' current status.
pub async fn get_agent_statuses(
    State(state): State<AppState>,
) -> Json<Vec<AgentStatusSnapshot>> {
    Json(state.core.status_registry.snapshot())
}
