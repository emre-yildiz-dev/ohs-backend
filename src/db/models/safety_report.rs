use serde::{Deserialize, Serialize};
use sqlx::types::Uuid;
use time::OffsetDateTime;
use validator::Validate;

#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type, Serialize, Deserialize)]
#[sqlx(type_name = "report_status", rename_all = "snake_case")]
pub enum ReportStatus {
    Open,
    InReview,
    Resolved,
    Archived,
}

#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type, Serialize, Deserialize)]
#[sqlx(type_name = "report_priority", rename_all = "snake_case")]
pub enum ReportPriority {
    Low,
    Medium,
    High,
    Critical,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct SafetyReport {
    pub id: Uuid,
    pub title: String,
    pub description: String,
    pub reporter_id: Option<Uuid>,  // Can be anonymous
    pub is_anonymous: bool,
    pub company_id: Uuid,
    pub status: ReportStatus,
    pub priority: ReportPriority,
    pub assigned_to: Option<Uuid>,
    pub location: Option<String>,
    pub images_urls: Option<Vec<String>>,
    pub resolved_at: Option<OffsetDateTime>,
    pub resolution_notes: Option<String>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct ReportComment {
    pub id: Uuid,
    pub report_id: Uuid,
    pub user_id: Option<Uuid>,  // Can be anonymous
    pub is_anonymous: bool,
    pub content: String,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
pub struct NewSafetyReport {
    #[validate(length(min = 1))]
    pub title: String,
    #[validate(length(min = 1))]
    pub description: String,
    pub reporter_id: Option<Uuid>,  // None if anonymous
    pub is_anonymous: bool,
    pub company_id: Uuid,
    pub priority: ReportPriority,
    pub location: Option<String>,
    pub images_urls: Option<Vec<String>>,
}

#[derive(Debug, Deserialize, Validate)]
pub struct UpdateSafetyReport {
    pub title: Option<String>,
    pub description: Option<String>,
    pub status: Option<ReportStatus>,
    pub priority: Option<ReportPriority>,
    pub assigned_to: Option<Uuid>,
    pub location: Option<String>,
    pub images_urls: Option<Vec<String>>,
    pub resolved_at: Option<OffsetDateTime>,
    pub resolution_notes: Option<String>,
}

#[derive(Debug, Deserialize, Validate)]
pub struct NewReportComment {
    pub report_id: Uuid,
    pub user_id: Option<Uuid>,  // None if anonymous
    pub is_anonymous: bool,
    #[validate(length(min = 1))]
    pub content: String,
} 