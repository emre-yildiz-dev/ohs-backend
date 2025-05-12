use serde::{Deserialize, Serialize};
use sqlx::types::Uuid;
use time::{OffsetDateTime, Duration};
use validator::Validate;

#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type, Serialize, Deserialize)]
#[sqlx(type_name = "appointment_status", rename_all = "snake_case")]
pub enum AppointmentStatus {
    Scheduled,
    Confirmed,
    Completed,
    Cancelled,
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
    pub employee_id: Uuid,
    pub specialist_id: Uuid,  // Either OhsSpecialist or Doctor
    pub company_id: Uuid,
    pub appointment_type: AppointmentType,
    pub status: AppointmentStatus,
    pub start_time: OffsetDateTime,
    pub end_time: OffsetDateTime,
    pub notes: Option<String>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
    pub cancelled_by: Option<Uuid>,
    pub cancellation_reason: Option<String>,
}

#[derive(Debug, Deserialize, Validate)]
pub struct NewAppointment {
    pub employee_id: Uuid,
    pub specialist_id: Uuid,
    pub company_id: Uuid,
    pub appointment_type: AppointmentType,
    pub start_time: OffsetDateTime,
    pub duration_minutes: i64,  // Will be used to calculate end_time
    pub notes: Option<String>,
}

impl NewAppointment {
    pub fn end_time(&self) -> OffsetDateTime {
        self.start_time + Duration::minutes(self.duration_minutes)
    }
}

#[derive(Debug, Deserialize, Validate)]
pub struct UpdateAppointment {
    pub status: Option<AppointmentStatus>,
    pub start_time: Option<OffsetDateTime>,
    pub end_time: Option<OffsetDateTime>,
    pub notes: Option<String>,
    pub cancelled_by: Option<Uuid>,
    pub cancellation_reason: Option<String>,
} 