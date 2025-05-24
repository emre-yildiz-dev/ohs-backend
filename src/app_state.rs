use std::sync::{Arc, Mutex};
use sqlx::PgPool;
use tokio::sync::broadcast;
use crate::config;
use crate::i18n::Localizer;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub env: config::Config,
    pub ws_tx: Arc<Mutex<broadcast::Sender<String>>>,
    pub localizer: Arc<Localizer>,
}

impl AppState {
    pub fn new(db: PgPool, env: config::Config, ws_tx: Arc<Mutex<broadcast::Sender<String>>>, localizer: Arc<Localizer>) -> Self {
        Self { db, env, ws_tx, localizer }
    }
}
