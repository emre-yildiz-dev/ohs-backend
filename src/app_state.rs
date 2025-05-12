use std::sync::{Arc, Mutex};
use sqlx::PgPool;
use tokio::sync::broadcast;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub ws_tx: Arc<Mutex<broadcast::Sender<String>>>,
}

impl AppState {
    pub fn new(db: PgPool, ws_tx: Arc<Mutex<broadcast::Sender<String>>>) -> Self {
        Self { db, ws_tx }
    }
}
