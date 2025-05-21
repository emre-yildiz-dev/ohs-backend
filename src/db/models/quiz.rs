use serde::{Deserialize, Serialize};
use sqlx::types::Uuid;
use time::OffsetDateTime;
use validator::Validate;

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct TrainingQuiz {
    pub id: Uuid,
    pub tenant_id: Uuid,
    pub training_session_id: Uuid,
    pub title: String,
    pub description: Option<String>,
    pub created_by_user_id: Uuid,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct QuizQuestion {
    pub id: Uuid,
    pub quiz_id: Uuid,
    pub tenant_id: Uuid,
    pub question_text: String,
    pub question_type: String,
    pub options: Option<serde_json::Value>,
    pub correct_answer_key: Option<String>,
    pub points: i32,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct QuizAttempt {
    pub id: Uuid,
    pub quiz_id: Uuid,
    pub enrollment_id: Option<Uuid>,
    pub employee_user_id: Uuid,
    pub tenant_id: Uuid,
    pub company_id: Uuid,
    pub started_at: OffsetDateTime,
    pub completed_at: Option<OffsetDateTime>,
    pub score: Option<f64>,
    pub passed: Option<bool>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct QuizAttemptAnswer {
    pub id: Uuid,
    pub attempt_id: Uuid,
    pub question_id: Uuid,
    pub tenant_id: Uuid,
    pub answer_key: Option<String>,
    pub answer_text: Option<String>,
    pub is_correct: Option<bool>,
    pub submitted_at: OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
pub struct NewTrainingQuiz {
    pub tenant_id: Uuid,
    pub training_session_id: Uuid,
    #[validate(length(min = 1))]
    pub title: String,
    pub description: Option<String>,
    pub created_by_user_id: Uuid,
}

#[derive(Debug, Deserialize, Validate)]
pub struct NewQuizQuestion {
    pub quiz_id: Uuid,
    pub tenant_id: Uuid,
    #[validate(length(min = 1))]
    pub question_text: String,
    pub question_type: String,
    pub options: Option<serde_json::Value>,
    pub correct_answer_key: Option<String>,
    pub points: Option<i32>,
}

#[derive(Debug, Deserialize, Validate)]
pub struct NewQuizAttempt {
    pub quiz_id: Uuid,
    pub enrollment_id: Option<Uuid>,
    pub employee_user_id: Uuid,
    pub tenant_id: Uuid,
    pub company_id: Uuid,
}

#[derive(Debug, Deserialize, Validate)]
pub struct NewQuizAttemptAnswer {
    pub attempt_id: Uuid,
    pub question_id: Uuid,
    pub tenant_id: Uuid,
    pub answer_key: Option<String>,
    pub answer_text: Option<String>,
}

#[derive(Debug, Deserialize, Validate)]
pub struct UpdateQuizAttempt {
    pub completed_at: Option<OffsetDateTime>,
    pub score: Option<f64>,
    pub passed: Option<bool>,
}

#[derive(Debug, Deserialize, Validate)]
pub struct UpdateQuizQuestion {
    pub question_text: Option<String>,
    pub question_type: Option<String>,
    pub options: Option<serde_json::Value>,
    pub correct_answer_key: Option<String>,
    pub points: Option<i32>,
} 