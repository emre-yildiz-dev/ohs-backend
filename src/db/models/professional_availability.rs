use serde::{Deserialize, Serialize};
use sqlx::types::Uuid;
use time::OffsetDateTime;
use validator::Validate;

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct ProfessionalAvailability {
    pub id: Uuid,
    pub professional_user_id: Uuid,
    pub tenant_id: Uuid,
    pub start_time: OffsetDateTime,
    pub end_time: OffsetDateTime,
    pub created_at: OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
pub struct NewProfessionalAvailability {
    pub professional_user_id: Uuid,
    pub tenant_id: Uuid,
    pub start_time: OffsetDateTime,
    pub end_time: OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
pub struct UpdateProfessionalAvailability {
    pub start_time: Option<OffsetDateTime>,
    pub end_time: Option<OffsetDateTime>,
} 