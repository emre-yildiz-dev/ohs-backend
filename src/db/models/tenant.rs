use serde::{Deserialize, Serialize};
use sqlx::types::Uuid;
use time::OffsetDateTime;
use validator::Validate;

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct Tenant {
    pub id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub owner_user_id: Option<Uuid>,
    pub is_active: bool,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct NewTenant {
    #[validate(length(min = 1, message = "Name must not be empty"))]
    pub name: String,
    pub description: Option<String>,
    pub owner_user_id: Option<Uuid>,
    pub is_active: Option<bool>,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct UpdateTenant {
    pub name: Option<String>,
    pub description: Option<String>,
    pub owner_user_id: Option<Uuid>,
    pub is_active: Option<bool>,
} 