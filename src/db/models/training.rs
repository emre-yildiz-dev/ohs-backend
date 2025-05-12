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

#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type, Serialize, Deserialize)]
#[sqlx(type_name = "participant_status", rename_all = "snake_case")]
pub enum ParticipantStatus {
    Registered,
    Attended,
    Completed,
    NoShow,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct Training {
    pub id: Uuid,
    pub title: String,
    pub description: Option<String>,
    pub specialist_id: Uuid,
    pub company_id: Uuid,
    pub training_type: TrainingType,
    pub status: TrainingStatus,
    pub start_time: OffsetDateTime,
    pub end_time: Option<OffsetDateTime>,
    pub duration_minutes: i64,
    pub max_participants: Option<i32>,
    pub material_url: Option<String>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct TrainingParticipant {
    pub id: Uuid,
    pub training_id: Uuid,
    pub user_id: Uuid,
    pub status: ParticipantStatus,
    pub joined_at: Option<OffsetDateTime>,
    pub completed_at: Option<OffsetDateTime>,
    pub feedback: Option<String>,
    pub rating: Option<i32>,
    pub certificate_url: Option<String>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
pub struct NewTraining {
    #[validate(length(min = 1))]
    pub title: String,
    pub description: Option<String>,
    pub specialist_id: Uuid,
    pub company_id: Uuid,
    pub training_type: TrainingType,
    pub start_time: OffsetDateTime,
    pub duration_minutes: i64,
    pub max_participants: Option<i32>,
    pub material_url: Option<String>,
}

#[derive(Debug, Deserialize, Validate)]
pub struct UpdateTraining {
    pub title: Option<String>,
    pub description: Option<String>,
    pub status: Option<TrainingStatus>,
    pub start_time: Option<OffsetDateTime>,
    pub end_time: Option<OffsetDateTime>,
    pub duration_minutes: Option<i64>,
    pub max_participants: Option<i32>,
    pub material_url: Option<String>,
}

#[derive(Debug, Deserialize, Validate)]
pub struct NewTrainingParticipant {
    pub training_id: Uuid,
    pub user_id: Uuid,
}

#[derive(Debug, Deserialize, Validate)]
pub struct UpdateParticipantStatus {
    pub status: ParticipantStatus,
    pub joined_at: Option<OffsetDateTime>,
    pub completed_at: Option<OffsetDateTime>,
    pub feedback: Option<String>,
    pub rating: Option<i32>,
    pub certificate_url: Option<String>,
} 