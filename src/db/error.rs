use thiserror::Error;

#[derive(Error, Debug)]
#[allow(unused)]
pub enum DatabaseError {
    #[error("Database error: {0}")]
    Sqlx(#[from] sqlx::Error),
    
    #[error("Record not found")]
    NotFound,
    
    #[error("Duplicate record")]
    Duplicate,
    
    #[error("Invalid input: {0}")]
    InvalidInput(String),
    
    #[error("Unauthorized access")]
    Unauthorized,
    
    #[error("Database connection error: {0}")]
    ConnectionError(String),
    
    #[error("Migration error: {0}")]
    MigrationError(String),
    
    #[error("Transaction error: {0}")]
    TransactionError(String),
    
    #[error("Unknown database error: {0}")]
    Unknown(String),
} 