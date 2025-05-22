use serde::{Deserialize, Serialize};
use sqlx::types::Uuid;
use time::OffsetDateTime;
use validator::Validate;

#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type, Serialize, Deserialize)]
#[sqlx(type_name = "user_role", rename_all = "snake_case")]
pub enum UserRole {
    SuperAdmin,
    TenantAdmin,
    OhsSpecialist,
    Doctor,
    Employee,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct UserTenantContextRole {
    pub id: Uuid,
    pub user_id: Uuid,
    pub role: UserRole,
    pub tenant_id: Option<Uuid>,
    pub company_id: Option<Uuid>,
    pub created_at: OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct NewUserTenantContextRole {
    pub user_id: Uuid,
    pub role: UserRole,
    pub tenant_id: Option<Uuid>,
    pub company_id: Option<Uuid>,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct UpdateUserTenantContextRole {
    pub role: Option<UserRole>,
    pub tenant_id: Option<Uuid>,
    pub company_id: Option<Uuid>,
} 