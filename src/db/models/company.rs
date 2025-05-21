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
    pub tenant_id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub status: CompanyStatus,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct CompanyProfile {
    pub id: Uuid,
    pub company_id: Uuid,
    pub address: Option<String>,
    pub contact_email: Option<String>,
    pub contact_phone: Option<String>,
    pub city: Option<String>,
    pub state: Option<String>,
    pub country: Option<String>,
    pub zip_code: Option<String>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

pub struct CompanyDetailsDto {
    pub id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub status: CompanyStatus,
    pub contact_email: Option<String>,
    pub contact_phone: Option<String>,
    pub city: Option<String>,
    pub state: Option<String>,
    pub country: Option<String>,
    pub zip_code: Option<String>,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct NewCompanyData {
    pub tenant_id: Uuid,
    #[validate(length(min = 1, message = "Name must be at least 1 character long"))]
    pub name: String,
    pub description: Option<String>,
    // status will default to 'active' as per SQL schema
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct NewCompanyProfileData {
    #[validate(email(message = "Invalid email address"))]
    pub contact_email: Option<String>,
    pub contact_phone: Option<String>,
    pub city: Option<String>,
    pub state: Option<String>,
    pub zip_code: Option<String>,
    pub country: Option<String>,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
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

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct CreateCompanyPayload {
    #[validate(nested)]
    pub company: NewCompanyData,
    #[validate(nested)]
    pub profile: Option<NewCompanyProfileData>,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct UpdateCompanyData {
    pub name: Option<String>,
    pub status: Option<CompanyStatus>,
    pub description: Option<String>,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct UpdateCompanyProfileData {
    pub address: Option<String>,
    pub contact_email: Option<String>,
    pub contact_phone: Option<String>,
    pub city: Option<String>,
    pub state: Option<String>,
    pub country: Option<String>,
    pub zip_code: Option<String>,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct UpdateCompanyPayload {
    #[validate(nested)]
    pub company: Option<UpdateCompanyData>,
    #[validate(nested)]
    pub profile: Option<UpdateCompanyProfileData>,
}

