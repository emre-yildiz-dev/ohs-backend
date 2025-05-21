use serde::{Deserialize, Serialize};
use sqlx::types::Uuid;
use time::OffsetDateTime;
use validator::Validate;

#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type, Serialize, Deserialize)]
#[sqlx(type_name = "training_material_type", rename_all = "snake_case")]
pub enum TrainingMaterialType {
    Video,
    Pdf,
    Slides,
    Other,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct TrainingMaterial {
    pub id: Uuid,
    pub tenant_id: Uuid,
    pub uploader_user_id: Uuid,
    pub training_session_id: Option<Uuid>,
    pub title: String,
    pub description: Option<String>,
    pub material_type: TrainingMaterialType,
    pub file_s3_key: String,
    pub file_size_bytes: Option<i64>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
pub struct NewTrainingMaterial {
    pub tenant_id: Uuid,
    pub uploader_user_id: Uuid,
    pub training_session_id: Option<Uuid>,
    #[validate(length(min = 1))]
    pub title: String,
    pub description: Option<String>,
    pub material_type: TrainingMaterialType,
    pub file_s3_key: String,
    pub file_size_bytes: Option<i64>,
}

#[derive(Debug, Deserialize, Validate)]
pub struct UpdateTrainingMaterial {
    pub title: Option<String>,
    pub description: Option<String>,
    pub training_session_id: Option<Uuid>,
} 