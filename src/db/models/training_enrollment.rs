use serde::{Deserialize, Serialize};
use sqlx::types::Uuid;
use time::OffsetDateTime;
use validator::Validate;

#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type, Serialize, Deserialize)]
#[sqlx(type_name = "participant_status", rename_all = "snake_case")]
pub enum ParticipantStatus {
    Registered,
    Attended,
    Completed,
    NoShow,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct TrainingEnrollment {
    pub id: Uuid,
    pub tenant_id: Uuid,
    pub training_session_id: Uuid,
    pub employee_user_id: Uuid,
    pub company_id: Uuid,
    pub status: ParticipantStatus,
    pub enrolled_at: OffsetDateTime,
    pub attended: bool,
    pub completion_date: Option<OffsetDateTime>,
    pub certificate_s3_key: Option<String>,
    pub feedback_rating: Option<i16>,
    pub feedback_text: Option<String>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct NewTrainingEnrollment {
    pub tenant_id: Uuid,
    pub training_session_id: Uuid,
    pub employee_user_id: Uuid,
    pub company_id: Uuid,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct UpdateTrainingEnrollment {
    pub status: Option<ParticipantStatus>,
    pub attended: Option<bool>,
    pub completion_date: Option<OffsetDateTime>,
    pub certificate_s3_key: Option<String>,
    #[validate(range(min = 1, max = 5))]
    pub feedback_rating: Option<i16>,
    pub feedback_text: Option<String>,
} 