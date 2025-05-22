use serde::{Deserialize, Serialize};
use sqlx::types::Uuid;
use time::OffsetDateTime;
use validator::Validate;

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
#[allow(unused)]
pub struct CallLog {
    pub id: Uuid,
    pub tenant_id: Uuid,
    pub appointment_id: Option<Uuid>,
    pub initiator_user_id: Uuid,
    pub receiver_user_id: Uuid,
    pub start_time: OffsetDateTime,
    pub end_time: Option<OffsetDateTime>,
    pub duration_seconds: Option<i32>,
    pub mediasoup_session_info: Option<serde_json::Value>,
    pub created_at: OffsetDateTime,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
#[allow(unused)]
pub struct SessionChat {
    pub id: Uuid,
    pub tenant_id: Uuid,
    pub training_session_id: Option<Uuid>,
    pub appointment_id: Option<Uuid>,
    pub is_active: bool,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
#[allow(unused)]
pub struct ChatMessage {
    pub id: Uuid,
    pub chat_id: Uuid,
    pub sender_user_id: Uuid,
    pub tenant_id: Uuid,
    pub content: String,
    pub sent_at: OffsetDateTime,
    pub is_deleted: bool,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct NewCallLog {
    pub tenant_id: Uuid,
    pub appointment_id: Option<Uuid>,
    pub initiator_user_id: Uuid,
    pub receiver_user_id: Uuid,
    pub start_time: OffsetDateTime,
    pub mediasoup_session_info: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct UpdateCallLog {
    pub end_time: Option<OffsetDateTime>,
    pub duration_seconds: Option<i32>,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct NewSessionChat {
    pub tenant_id: Uuid,
    pub training_session_id: Option<Uuid>,
    pub appointment_id: Option<Uuid>,
    pub is_active: Option<bool>,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct UpdateSessionChat {
    pub is_active: Option<bool>,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct NewChatMessage {
    pub chat_id: Uuid,
    pub sender_user_id: Uuid,
    pub tenant_id: Uuid,
    #[validate(length(min = 1))]
    pub content: String,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct DeleteChatMessage {
    pub is_deleted: bool,
} 