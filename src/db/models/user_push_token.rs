use serde::{Deserialize, Serialize};
use sqlx::types::Uuid;
use time::OffsetDateTime;
use validator::Validate;

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct UserPushToken {
    pub id: Uuid,
    pub user_id: Uuid,
    pub token: String,
    pub device_name: Option<String>,
    pub last_used_at: OffsetDateTime,
    pub created_at: OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
pub struct NewUserPushToken {
    pub user_id: Uuid,
    #[validate(length(min = 1))]
    pub token: String,
    pub device_name: Option<String>,
}

#[derive(Debug, Deserialize, Validate)]
pub struct UpdateUserPushToken {
    pub device_name: Option<String>,
    pub last_used_at: Option<OffsetDateTime>,
} 