use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;
use thiserror::Error;

use crate::db::DatabaseError;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("Database error: {0}")]
    Database(#[from] DatabaseError),

    #[error("Authentication error: {0}")]
    Authentication(String),

    #[error("Authorization error: {0}")]
    Authorization(String),

    #[error("Validation error: {0}")]
    Validation(String),

    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Conflict: {0}")]
    Conflict(String),

    #[error("Internal server error: {0}")]
    InternalServerError(String),

    #[error("Bad request: {0}")]
    BadRequest(String),

    #[error("Service unavailable: {0}")]
    ServiceUnavailable(String),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, error_message) = match self {
            AppError::Database(ref err) => match err {
                DatabaseError::NotFound => (StatusCode::NOT_FOUND, "Resource not found"),
                DatabaseError::Duplicate => (StatusCode::CONFLICT, "Resource already exists"),
                DatabaseError::InvalidInput(_) => (StatusCode::BAD_REQUEST, "Invalid input data"),
                DatabaseError::Unauthorized => (StatusCode::UNAUTHORIZED, "Unauthorized access"),
                _ => (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "An internal server error occurred",
                ),
            },
            AppError::Authentication(_) => (StatusCode::UNAUTHORIZED, "Authentication failed"),
            AppError::Authorization(_) => (StatusCode::FORBIDDEN, "Access denied"),
            AppError::Validation(_) => (StatusCode::BAD_REQUEST, "Validation error"),
            AppError::NotFound(_) => (StatusCode::NOT_FOUND, "Resource not found"),
            AppError::Conflict(_) => (StatusCode::CONFLICT, "Resource conflict"),
            AppError::InternalServerError(_) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "An internal server error occurred",
            ),
            AppError::BadRequest(_) => (StatusCode::BAD_REQUEST, "Bad request"),
            AppError::ServiceUnavailable(_) => (
                StatusCode::SERVICE_UNAVAILABLE,
                "Service unavailable",
            ),
        };

        let body = Json(json!({
            "error": {
                "message": error_message,
                "details": self.to_string(),
            }
        }));

        (status, body).into_response()
    }
}

pub type AppResult<T> = Result<T, AppError>;
