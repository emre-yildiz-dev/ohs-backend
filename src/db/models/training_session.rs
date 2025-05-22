use serde::{Deserialize, Serialize};
use sqlx::types::Uuid;
use time::OffsetDateTime;
use validator::Validate;

#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type, Serialize, Deserialize)]
#[sqlx(type_name = "training_status", rename_all = "snake_case")]
pub enum TrainingStatus {
    Scheduled,
    InProgress,
    Completed,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type, Serialize, Deserialize)]
#[sqlx(type_name = "training_type", rename_all = "snake_case")]
pub enum TrainingType {
    LiveWebinar,
    RecordedVideo,
    Document,
    Quiz,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct TrainingSession {
    pub id: Uuid,
    pub tenant_id: Uuid,
    pub host_user_id: Uuid,
    pub title: String,
    pub description: Option<String>,
    pub training_type: TrainingType,
    pub status: TrainingStatus,
    pub start_time: OffsetDateTime,
    pub end_time: OffsetDateTime,
    pub stream_details: Option<serde_json::Value>,
    pub max_participants: Option<i32>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct NewTrainingSession {
    pub tenant_id: Uuid,
    pub host_user_id: Uuid,
    #[validate(length(min = 1))]
    pub title: String,
    pub description: Option<String>,
    pub training_type: TrainingType,
    pub start_time: OffsetDateTime,
    pub end_time: OffsetDateTime,
    pub stream_details: Option<serde_json::Value>,
    pub max_participants: Option<i32>,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct UpdateTrainingSession {
    pub title: Option<String>,
    pub description: Option<String>,
    pub training_type: Option<TrainingType>,
    pub status: Option<TrainingStatus>,
    pub start_time: Option<OffsetDateTime>,
    pub end_time: Option<OffsetDateTime>,
    pub stream_details: Option<serde_json::Value>,
    pub max_participants: Option<i32>,
} 