use serde::{Deserialize, Serialize};
use sqlx::types::Uuid;
use time::OffsetDateTime;
use validator::Validate;

#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type, Serialize, Deserialize)]
#[sqlx(type_name = "notification_type", rename_all = "snake_case")]
pub enum NotificationType {
    AppointmentReminder,
    AppointmentConfirmed,
    AppointmentCancelled,
    TrainingReminder,
    TrainingRegistration,
    TrainingCancelled,
    SafetyReportUpdate,
    SystemMessage,
    NewMessage,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct Notification {
    pub id: Uuid,
    pub user_id: Uuid,
    pub notification_type: NotificationType,
    pub title: String,
    pub message: String,
    pub is_read: bool,
    pub reference_id: Option<Uuid>,  // Related entity ID (appointment, training, etc.)
    pub reference_type: Option<String>,  // Type of the referenced entity
    pub created_at: OffsetDateTime,
    pub read_at: Option<OffsetDateTime>,
    pub expires_at: Option<OffsetDateTime>,
}

#[derive(Debug, Deserialize, Validate)]
pub struct NewNotification {
    pub user_id: Uuid,
    pub notification_type: NotificationType,
    #[validate(length(min = 1))]
    pub title: String,
    #[validate(length(min = 1))]
    pub message: String,
    pub reference_id: Option<Uuid>,
    pub reference_type: Option<String>,
    pub expires_at: Option<OffsetDateTime>,
}

#[derive(Debug, Deserialize, Validate)]
pub struct MarkNotificationRead {
    pub is_read: bool,
} 