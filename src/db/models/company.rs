use serde::{Deserialize, Serialize};
use sqlx::types::Uuid;
use time::OffsetDateTime;
use validator::Validate;

#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type, Serialize, Deserialize)]
#[sqlx(type_name = "company_status", rename_all = "snake_case")]
pub enum CompanyStatus {
    Active,
    Inactive,
    Suspended,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct Company {
    pub id: Uuid,
    pub name: String,
    pub status: CompanyStatus,
    pub address: Option<String>,
    pub city: Option<String>,
    pub state: Option<String>,
    pub country: Option<String>,
    pub postal_code: Option<String>,
    pub website: Option<String>,
    pub phone_number: Option<String>,
    pub logo_url: Option<String>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
pub struct NewCompany {
    #[validate(length(min = 1))]
    pub name: String,
    pub address: Option<String>,
    pub city: Option<String>,
    pub state: Option<String>,
    pub country: Option<String>,
    pub postal_code: Option<String>,
    pub website: Option<String>,
    pub phone_number: Option<String>,
}

#[derive(Debug, Deserialize, Validate)]
pub struct UpdateCompany {
    pub name: Option<String>,
    pub status: Option<CompanyStatus>,
    pub address: Option<String>,
    pub city: Option<String>,
    pub state: Option<String>,
    pub country: Option<String>,
    pub postal_code: Option<String>,
    pub website: Option<String>,
    pub phone_number: Option<String>,
    pub logo_url: Option<String>,
} 