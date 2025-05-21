use serde::{Deserialize, Serialize};
use sqlx::types::Uuid;
use time::{Date, OffsetDateTime};
use validator::Validate;

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct UserProfile {
    pub user_id: Uuid,
    pub first_name: String,
    pub last_name: String,
    pub date_of_birth: Option<Date>,
    pub gender: Option<String>,
    pub phone_number: Option<String>,
    pub profile_picture_url: Option<String>,
    pub company_id: Option<Uuid>,
    pub department: Option<String>,
    pub job_title: Option<String>,
    pub address: Option<String>,
    pub city: Option<String>,
    pub state: Option<String>,
    pub zip_code: Option<String>,
    pub country: Option<String>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
pub struct NewUserProfile {
    pub user_id: Uuid,
    #[validate(length(min = 1, message = "First name must not be empty"))]
    pub first_name: String,
    #[validate(length(min = 1, message = "Last name must not be empty"))]
    pub last_name: String,
    pub date_of_birth: Option<Date>,
    pub gender: Option<String>,
    pub phone_number: Option<String>,
    pub profile_picture_url: Option<String>,
    pub company_id: Option<Uuid>,
    pub department: Option<String>,
    pub job_title: Option<String>,
    pub address: Option<String>,
    pub city: Option<String>,
    pub state: Option<String>,
    pub zip_code: Option<String>,
    pub country: Option<String>,
}

#[derive(Debug, Deserialize, Validate)]
pub struct UpdateUserProfile {
    pub first_name: Option<String>,
    pub last_name: Option<String>,
    pub date_of_birth: Option<Date>,
    pub gender: Option<String>,
    pub phone_number: Option<String>,
    pub profile_picture_url: Option<String>,
    pub company_id: Option<Uuid>,
    pub department: Option<String>,
    pub job_title: Option<String>,
    pub address: Option<String>,
    pub city: Option<String>,
    pub state: Option<String>,
    pub zip_code: Option<String>,
    pub country: Option<String>,
} 