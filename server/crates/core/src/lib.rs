// relais-core: Core library for Relais
//
// Provides shared types, configuration management, PTY handling,
// session management, and foundational abstractions used by all
// other crates in the workspace.

pub mod agent;
pub mod config;
pub mod event_bus;
pub mod events;
pub mod pty;
pub mod session;
pub mod task_pool;

use std::sync::Arc;

/// Central application state owning all core components.
pub struct CoreState {
    pub config: Arc<config::Config>,
    pub event_bus: Arc<event_bus::EventBus>,
    pub pty_manager: Arc<pty::manager::PtyManager>,
    pub session_store: Arc<session::store::SessionStore>,
    pub agent_manager: Arc<agent::manager::AgentManager>,
    pub task_pool: Arc<task_pool::pool::TaskPool>,
    /// Handle to the background task dispatcher (dropped on shutdown).
    pub task_dispatcher_handle: Option<task_pool::scheduler::DispatcherHandle>,
}

impl CoreState {
    /// Initialize all core components from config.
    pub fn new(config: config::Config) -> anyhow::Result<Self> {
        crate::pty::tmux::validate_tmux()?;

        let config = Arc::new(config);
        let event_bus = Arc::new(event_bus::EventBus::new());

        let sessions_dir = config::Config::relais_dir()
            .map(|d| d.join("sessions"))
            .unwrap_or_else(|_| std::path::PathBuf::from("/tmp/relais/sessions"));
        let session_store = Arc::new(session::store::SessionStore::new(sessions_dir)?);

        let pty_manager = Arc::new(pty::manager::PtyManager::new(
            Arc::clone(&event_bus),
            Arc::clone(&config),
        ));

        let agent_manager = Arc::new(agent::manager::AgentManager::new(Arc::clone(&event_bus)));

        // Task pool backed by ~/.relais/tasks.jsonl
        let tasks_path = config::Config::relais_dir()
            .map(|d| d.join("tasks.jsonl"))
            .unwrap_or_else(|_| std::path::PathBuf::from("/tmp/relais/tasks.jsonl"));
        let task_pool = Arc::new(task_pool::pool::TaskPool::new(tasks_path));

        // Task dispatcher: auto-assigns pending tasks to idle agents.
        let scheduler_config =
            task_pool::scheduler::SchedulerConfig::from_pool_config(&config.task_pool);
        let dispatcher = task_pool::scheduler::TaskDispatcher::new(
            scheduler_config,
            Arc::clone(&task_pool),
            Arc::clone(&agent_manager),
            Arc::clone(&event_bus),
        );
        let dispatcher_handle = dispatcher.start();

        Ok(Self {
            config,
            event_bus,
            pty_manager,
            session_store,
            agent_manager,
            task_pool,
            task_dispatcher_handle: Some(dispatcher_handle),
        })
    }
}
