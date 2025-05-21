use serde::{Deserialize, Serialize};
use sqlx::types::Uuid;
use time::{OffsetDateTime, Duration};
use validator::Validate;

#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type, Serialize, Deserialize)]
#[sqlx(type_name = "appointment_status", rename_all = "snake_case")]
pub enum AppointmentStatus {
    Pending,
    Confirmed,
    Completed,
    CancelledByProfessional,
    CancelledByEmployee,
    NoShow,
}

#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type, Serialize, Deserialize)]
#[sqlx(type_name = "appointment_type", rename_all = "snake_case")]
pub enum AppointmentType {
    OhsConsultation,
    MedicalCheckup,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct Appointment {
    pub id: Uuid,
    pub tenant_id: Uuid,
    pub professional_user_id: Uuid,  // Either OhsSpecialist or Doctor
    pub employee_user_id: Uuid,
    pub company_id: Uuid,
    pub appointment_type: AppointmentType,
    pub status: AppointmentStatus,
    pub start_time: OffsetDateTime,
    pub end_time: OffsetDateTime,
    pub reason_for_visit: Option<String>,
    pub notes_by_professional: Option<String>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct NewAppointment {
    pub tenant_id: Uuid,
    pub professional_user_id: Uuid,
    pub employee_user_id: Uuid,
    pub company_id: Uuid,
    pub appointment_type: AppointmentType,
    #[validate(range(min = 1, message = "Duration must be at least 1 minute"))]
    pub duration_minutes: i64,
    pub start_time: OffsetDateTime,
    pub reason_for_visit: Option<String>,
    pub notes_by_professional: Option<String>,
}

#[allow(unused)]
impl NewAppointment {
    pub fn end_time(&self) -> OffsetDateTime {
        self.start_time + Duration::minutes(self.duration_minutes)
    }
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct UpdateAppointmentPayload {
    pub status: Option<AppointmentStatus>,
    pub start_time: Option<OffsetDateTime>,
    pub end_time: Option<OffsetDateTime>,
    pub reason_for_visit: Option<String>,
    pub notes_by_professional: Option<String>,
} 