use serde::{Deserialize, Serialize};
use sqlx::types::Uuid;
use secrecy::SecretBox;
use time::OffsetDateTime;
use validator::Validate;

#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type, Serialize, Deserialize)]
#[sqlx(type_name = "user_role", rename_all = "snake_case")]
pub enum UserRole {
    Employee,
    OhsSpecialist,
    Doctor,
    Admin,
    SuperAdmin,
}

#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type, Serialize, Deserialize)]
#[sqlx(type_name = "user_status", rename_all = "snake_case")]
pub enum UserStatus {
    Active,
    Inactive,
    Pending,
    Suspended,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct User {
    pub id: Uuid,
    pub email: String,
    #[serde(skip_serializing)]
    pub password_hash: String,
    pub first_name: String,
    pub last_name: String,
    pub role: UserRole,
    pub status: UserStatus,
    pub company_id: Option<Uuid>,
    pub department: Option<String>,
    pub job_title: Option<String>,
    pub profile_image_url: Option<String>,
    pub phone_number: Option<String>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
    pub last_login_at: Option<OffsetDateTime>,
}

#[derive(Debug, Deserialize, Validate)]
pub struct NewUser {
    #[validate(email)]
    pub email: String,
    pub password: SecretBox<String>,
    #[validate(length(min = 1))]
    pub first_name: String,
    #[validate(length(min = 1))]
    pub last_name: String,
    pub role: UserRole,
    pub company_id: Option<Uuid>,
    pub department: Option<String>,
    pub job_title: Option<String>,
    pub phone_number: Option<String>,
}

#[derive(Debug, Deserialize, Validate)]
pub struct UpdateUser {
    pub first_name: Option<String>,
    pub last_name: Option<String>,
    pub department: Option<String>,
    pub job_title: Option<String>,
    pub profile_image_url: Option<String>,
    pub phone_number: Option<String>,
    pub status: Option<UserStatus>,
    pub company_id: Option<Uuid>,
}

#[derive(Debug, Deserialize, Validate)]
pub struct UserLogin {
    #[validate(email)]
    pub email: String,
    pub password: SecretBox<String>,
} 