use serde::{Deserialize, Serialize};
use sqlx::types::Uuid;
use time::OffsetDateTime;
use validator::Validate;

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
#[allow(unused)]
pub struct SystemSetting {
    pub id: Uuid,
    pub tenant_id: Option<Uuid>,
    pub setting_key: String,
    pub setting_value: serde_json::Value,
    pub description: Option<String>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct NewSystemSetting {
    pub tenant_id: Option<Uuid>,
    #[validate(length(min = 1))]
    pub setting_key: String,
    pub setting_value: serde_json::Value,
    pub description: Option<String>,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct UpdateSystemSetting {
    pub setting_value: Option<serde_json::Value>,
    pub description: Option<String>,
} 