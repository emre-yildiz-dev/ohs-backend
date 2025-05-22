use serde::{Deserialize, Serialize};
use sqlx::types::Uuid;
use time::OffsetDateTime;
use validator::Validate;

#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type, Serialize, Deserialize)]
#[sqlx(type_name = "risk_analysis_check_status", rename_all = "snake_case")]
#[allow(unused)]
pub enum RiskAnalysisCheckStatus {
    Draft,
    Submitted,
    InReview,
    Completed,
    Archived,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct RiskAnalysisTemplate {
    pub id: Uuid,
    pub tenant_id: Uuid,
    pub creator_user_id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub structure_json: serde_json::Value,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct RiskAnalysisCheck {
    pub id: Uuid,
    pub tenant_id: Uuid,
    pub company_id: Uuid,
    pub template_id: Uuid,
    pub checker_user_id: Uuid,
    pub status: RiskAnalysisCheckStatus,
    pub data_json: serde_json::Value,
    pub overall_risk_score: Option<f64>,
    pub recommendations: Option<String>,
    pub checked_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct NewRiskAnalysisTemplate {
    pub tenant_id: Uuid,
    pub creator_user_id: Uuid,
    #[validate(length(min = 1))]
    pub name: String,
    pub description: Option<String>,
    pub structure_json: serde_json::Value,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct UpdateRiskAnalysisTemplate {
    pub name: Option<String>,
    pub description: Option<String>,
    pub structure_json: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct NewRiskAnalysisCheck {
    pub tenant_id: Uuid,
    pub company_id: Uuid,
    pub template_id: Uuid,
    pub checker_user_id: Uuid,
    pub status: RiskAnalysisCheckStatus,
    pub data_json: serde_json::Value,
    pub overall_risk_score: Option<f64>,
    pub recommendations: Option<String>,
}

#[derive(Debug, Deserialize, Validate)]
#[allow(unused)]
pub struct UpdateRiskAnalysisCheck {
    pub status: Option<RiskAnalysisCheckStatus>,
    pub data_json: Option<serde_json::Value>,
    pub overall_risk_score: Option<f64>,
    pub recommendations: Option<String>,
} 