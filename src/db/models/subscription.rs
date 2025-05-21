use serde::{Deserialize, Serialize};
use sqlx::types::Uuid;
use time::OffsetDateTime;
use validator::Validate;

#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type, Serialize, Deserialize)]
#[sqlx(type_name = "subscription_plan_status", rename_all = "snake_case")]
pub enum SubscriptionPlanStatus {
    Active,
    Deprecated,
    Inactive,
}

#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type, Serialize, Deserialize)]
#[sqlx(type_name = "tenant_subscription_status", rename_all = "snake_case")]
pub enum TenantSubscriptionStatus {
    Active,
    PastDue,
    Cancelled,
    Expired,
    Trialing,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct SubscriptionPlan {
    pub id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub price_monthly: f64,
    pub currency: String,
    pub status: SubscriptionPlanStatus,
    pub max_companies: Option<i32>,
    pub max_employees_total: Option<i32>,
    pub max_doctors: Option<i32>,
    pub max_ohs_specialists: Option<i32>,
    pub live_session_time_limit_minutes: Option<i32>,
    pub storage_limit_gb: Option<i32>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
pub struct NewSubscriptionPlan {
    #[validate(length(min = 1, message = "Name must not be empty"))]
    pub name: String,
    pub description: Option<String>,
    #[validate(range(min = 0.0, message = "Price cannot be negative"))]
    pub price_monthly: f64,
    #[validate(length(min = 3, max = 3))]
    pub currency: String,
    pub status: SubscriptionPlanStatus,
    pub max_companies: Option<i32>,
    pub max_employees_total: Option<i32>,
    pub max_doctors: Option<i32>,
    pub max_ohs_specialists: Option<i32>,
    pub live_session_time_limit_minutes: Option<i32>,
    pub storage_limit_gb: Option<i32>,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize, Deserialize)]
pub struct TenantSubscription {
    pub id: Uuid,
    pub tenant_id: Uuid,
    pub plan_id: Uuid,
    pub status: TenantSubscriptionStatus,
    pub start_date: OffsetDateTime,
    pub end_date: Option<OffsetDateTime>,
    pub trial_ends_at: Option<OffsetDateTime>,
    pub payment_gateway_customer_id: Option<String>,
    pub payment_gateway_subscription_id: Option<String>,
    pub custom_max_companies: Option<i32>,
    pub custom_max_employees_total: Option<i32>,
    pub custom_max_doctors: Option<i32>,
    pub custom_max_ohs_specialists: Option<i32>,
    pub custom_live_session_time_limit_minutes: Option<i32>,
    pub custom_storage_limit_gb: Option<i32>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Deserialize, Validate)]
pub struct NewTenantSubscription {
    pub tenant_id: Uuid,
    pub plan_id: Uuid,
    pub status: Option<TenantSubscriptionStatus>,
    pub start_date: Option<OffsetDateTime>,
    pub end_date: Option<OffsetDateTime>,
    pub trial_ends_at: Option<OffsetDateTime>,
    pub payment_gateway_customer_id: Option<String>,
    pub payment_gateway_subscription_id: Option<String>,
    pub custom_max_companies: Option<i32>,
    pub custom_max_employees_total: Option<i32>,
    pub custom_max_doctors: Option<i32>,
    pub custom_max_ohs_specialists: Option<i32>,
    pub custom_live_session_time_limit_minutes: Option<i32>,
    pub custom_storage_limit_gb: Option<i32>,
}

#[derive(Debug, Deserialize, Validate)]
pub struct UpdateTenantSubscription {
    pub plan_id: Option<Uuid>,
    pub status: Option<TenantSubscriptionStatus>,
    pub end_date: Option<OffsetDateTime>,
    pub trial_ends_at: Option<OffsetDateTime>,
    pub payment_gateway_customer_id: Option<String>,
    pub payment_gateway_subscription_id: Option<String>,
    pub custom_max_companies: Option<i32>,
    pub custom_max_employees_total: Option<i32>,
    pub custom_max_doctors: Option<i32>,
    pub custom_max_ohs_specialists: Option<i32>,
    pub custom_live_session_time_limit_minutes: Option<i32>,
    pub custom_storage_limit_gb: Option<i32>,
} 