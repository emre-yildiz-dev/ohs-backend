use serde::{Deserialize, Serialize};
use sqlx::types::Uuid;
use time::OffsetDateTime;
use validator::Validate;

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
#[allow(unused)]
pub struct OhsSpecialistCompanyAssignment {
    pub id: Uuid,
    pub ohs_specialist_user_id: Uuid,
    pub company_id: Uuid,
    pub tenant_id: Uuid,
    pub created_at: OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct NewOhsSpecialistCompanyAssignment {
    pub ohs_specialist_user_id: Uuid,
    pub company_id: Uuid,
    pub tenant_id: Uuid,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
#[allow(unused)]
pub struct DoctorCompanyAssignment {
    pub id: Uuid,
    pub doctor_user_id: Uuid,
    pub company_id: Uuid,
    pub tenant_id: Uuid,
    pub created_at: OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct NewDoctorCompanyAssignment {
    pub doctor_user_id: Uuid,
    pub company_id: Uuid,
    pub tenant_id: Uuid,
} 