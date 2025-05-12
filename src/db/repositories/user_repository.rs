use crate::db::{DatabaseError, User, UserRole, UserStatus, NewUser, UpdateUser};
use argon2::{password_hash::SaltString, Argon2, PasswordHasher};
use secrecy::{ExposeSecret, SecretBox};
use sqlx::{postgres::PgRow, PgPool, Postgres, Row, Transaction};
use sqlx::types::Uuid;
use time::OffsetDateTime;
use tracing::{error, info};

pub struct UserRepository;

#[allow(unused)]
impl UserRepository {
    // Hash a password with Argon2
    fn hash_password(password: &str) -> Result<String, DatabaseError> {
        let argon2 = Argon2::default();
        let salt = SaltString::generate(&mut argon2::password_hash::rand_core::OsRng);
        
        argon2
            .hash_password(password.as_bytes(), &salt)
            .map_err(|e| {
                error!("Password hashing error: {}", e);
                DatabaseError::Unknown(format!("Password hashing error: {}", e))
            })
            .map(|hash| hash.to_string())
    }

    // Create a new user
    pub async fn create(pool: &PgPool, new_user: NewUser) -> Result<User, DatabaseError> {
        let password_hash = Self::hash_password(new_user.password.expose_secret())?;

        let user = sqlx::query_as!(
            User,
            r#"
            INSERT INTO users (
                email, password_hash, first_name, last_name, role, company_id, 
                department, job_title, phone_number, status
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'pending')
            RETURNING 
                id, email, password_hash, first_name, last_name, 
                role as "role: _", status as "status: _", 
                company_id, department, job_title, profile_image_url, phone_number,
                created_at, updated_at, last_login_at
            "#,
            new_user.email,
            password_hash,
            new_user.first_name,
            new_user.last_name,
            new_user.role as UserRole,
            new_user.company_id,
            new_user.department,
            new_user.job_title,
            new_user.phone_number
        )
        .fetch_one(pool)
        .await
        .map_err(|e| {
            if let sqlx::Error::Database(ref db_error) = e {
                if db_error.constraint().is_some() && db_error.constraint().unwrap() == "users_email_key" {
                    return DatabaseError::Duplicate;
                }
            }
            DatabaseError::Sqlx(e)
        })?;

        info!("Created user {} with id {}", user.email, user.id);
        Ok(user)
    }

    // Find a user by their UUID
    pub async fn find_by_id(pool: &PgPool, id: Uuid) -> Result<User, DatabaseError> {
        let user = sqlx::query_as!(
            User,
            r#"
            SELECT 
                id, email, password_hash, first_name, last_name, 
                role as "role: _", status as "status: _", 
                company_id, department, job_title, profile_image_url, phone_number,
                created_at, updated_at, last_login_at
            FROM users
            WHERE id = $1
            "#,
            id
        )
        .fetch_optional(pool)
        .await?;

        user.ok_or(DatabaseError::NotFound)
    }

    // Find a user by their email
    pub async fn find_by_email(pool: &PgPool, email: &str) -> Result<User, DatabaseError> {
        let user = sqlx::query_as!(
            User,
            r#"
            SELECT 
                id, email, password_hash, first_name, last_name, 
                role as "role: _", status as "status: _", 
                company_id, department, job_title, profile_image_url, phone_number,
                created_at, updated_at, last_login_at
            FROM users
            WHERE email = $1
            "#,
            email
        )
        .fetch_optional(pool)
        .await?;

        user.ok_or(DatabaseError::NotFound)
    }

    // Update a user
    pub async fn update(pool: &PgPool, id: Uuid, update: UpdateUser) -> Result<User, DatabaseError> {
        let mut tx = pool.begin().await?;
        
        // Get the current user to make sure it exists
        let current_user = Self::find_by_id_tx(&mut tx, id).await?;
        
        // If no updates were provided, return the current user
        if update.is_empty() {
            tx.commit().await?;
            return Ok(current_user);
        }
        
        // Use a simpler approach with a prepared statement for each update scenario
        let user = match update {
            UpdateUser { first_name: Some(first_name), .. } if update.only_has_first_name() => {
                sqlx::query_as!(
                    User,
                    r#"
                    UPDATE users 
                    SET first_name = $1
                    WHERE id = $2
                    RETURNING 
                        id, email, password_hash, first_name, last_name, 
                        role as "role: _", status as "status: _", 
                        company_id, department, job_title, profile_image_url, phone_number,
                        created_at, updated_at, last_login_at
                    "#,
                    first_name,
                    id
                )
                .fetch_one(&mut *tx)
                .await?
            },
            // Add more specialized cases here
            _ => {
                // Otherwise, build a dynamic query
                Self::update_dynamic(&mut tx, id, update).await?
            }
        };
        
        tx.commit().await?;
        Ok(user)
    }

    // Helper method for dynamic updates
    async fn update_dynamic(
        tx: &mut Transaction<'_, Postgres>,
        id: Uuid,
        update: UpdateUser
    ) -> Result<User, DatabaseError> {
        let mut query_parts: Vec<String> = Vec::new();
        let mut params = Vec::new();
        
        if let Some(first_name) = update.first_name {
            query_parts.push("first_name = $1".to_string());
            params.push(first_name);
        }
        
        if let Some(last_name) = update.last_name {
            query_parts.push(format!("last_name = ${}", params.len() + 1));
            params.push(last_name);
        }
        
        if let Some(department) = update.department {
            query_parts.push(format!("department = ${}", params.len() + 1));
            params.push(department);
        }
        
        if let Some(job_title) = update.job_title {
            query_parts.push(format!("job_title = ${}", params.len() + 1));
            params.push(job_title);
        }
        
        if let Some(profile_image_url) = update.profile_image_url {
            query_parts.push(format!("profile_image_url = ${}", params.len() + 1));
            params.push(profile_image_url);
        }
        
        if let Some(phone_number) = update.phone_number {
            query_parts.push(format!("phone_number = ${}", params.len() + 1));
            params.push(phone_number);
        }
        
        if let Some(status) = update.status {
            query_parts.push(format!("status = ${}::user_status", params.len() + 1));
            params.push(status.to_string());
        }
        
        if let Some(company_id) = update.company_id {
            query_parts.push(format!("company_id = ${}::uuid", params.len() + 1));
            params.push(company_id.to_string());
        }
        
        // Construct the final query
        let set_clause = query_parts.join(", ");
        let query = format!(
            "UPDATE users SET {} WHERE id = ${}::uuid RETURNING 
                id, email, password_hash, first_name, last_name, 
                role, status, company_id, department, job_title, 
                profile_image_url, phone_number, created_at, updated_at, last_login_at",
            set_clause,
            params.len() + 1
        );
        
        // Create and execute the query
        let mut query_builder = sqlx::query(&query);
        
        // Add all parameters
        for param in params {
            query_builder = query_builder.bind(param);
        }
        
        // Add the id parameter
        query_builder = query_builder.bind(id);
        
        // Execute and convert to User
        let row = query_builder
            .fetch_one(&mut **tx)
            .await?;
            
        // Convert row to User
        let user = Self::row_to_user(row)?;
        
        Ok(user)
    }
    
    // Helper to convert a row to a User
    fn row_to_user(row: PgRow) -> Result<User, DatabaseError> {
        Ok(User {
            id: row.try_get("id")
                .map_err(|_| DatabaseError::Unknown("Failed to get id from row".to_string()))?,
            email: row.try_get("email")
                .map_err(|_| DatabaseError::Unknown("Failed to get email from row".to_string()))?,
            password_hash: row.try_get("password_hash")
                .map_err(|_| DatabaseError::Unknown("Failed to get password_hash from row".to_string()))?,
            first_name: row.try_get("first_name")
                .map_err(|_| DatabaseError::Unknown("Failed to get first_name from row".to_string()))?,
            last_name: row.try_get("last_name")
                .map_err(|_| DatabaseError::Unknown("Failed to get last_name from row".to_string()))?,
            role: row.try_get("role")
                .map_err(|_| DatabaseError::Unknown("Failed to get role from row".to_string()))?,
            status: row.try_get("status")
                .map_err(|_| DatabaseError::Unknown("Failed to get status from row".to_string()))?,
            company_id: row.try_get("company_id")
                .map_err(|_| DatabaseError::Unknown("Failed to get company_id from row".to_string()))?,
            department: row.try_get("department")
                .map_err(|_| DatabaseError::Unknown("Failed to get department from row".to_string()))?,
            job_title: row.try_get("job_title")
                .map_err(|_| DatabaseError::Unknown("Failed to get job_title from row".to_string()))?,
            profile_image_url: row.try_get("profile_image_url")
                .map_err(|_| DatabaseError::Unknown("Failed to get profile_image_url from row".to_string()))?,
            phone_number: row.try_get("phone_number")
                .map_err(|_| DatabaseError::Unknown("Failed to get phone_number from row".to_string()))?,
            created_at: row.try_get("created_at")
                .map_err(|_| DatabaseError::Unknown("Failed to get created_at from row".to_string()))?,
            updated_at: row.try_get("updated_at")
                .map_err(|_| DatabaseError::Unknown("Failed to get updated_at from row".to_string()))?,
            last_login_at: row.try_get("last_login_at")
                .map_err(|_| DatabaseError::Unknown("Failed to get last_login_at from row".to_string()))?,
        })
    }

    // Delete a user by ID
    pub async fn delete(pool: &PgPool, id: Uuid) -> Result<(), DatabaseError> {
        let result = sqlx::query!("DELETE FROM users WHERE id = $1", id)
            .execute(pool)
            .await?;
            
        if result.rows_affected() == 0 {
            return Err(DatabaseError::NotFound);
        }
        
        Ok(())
    }

    // List users by company ID with pagination
    pub async fn list_by_company(
        pool: &PgPool, 
        company_id: Uuid,
        limit: i64,
        offset: i64
    ) -> Result<Vec<User>, DatabaseError> {
        let users = sqlx::query_as!(
            User,
            r#"
            SELECT 
                id, email, password_hash, first_name, last_name, 
                role as "role: _", status as "status: _", 
                company_id, department, job_title, profile_image_url, phone_number,
                created_at, updated_at, last_login_at
            FROM users
            WHERE company_id = $1
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#,
            company_id,
            limit,
            offset
        )
        .fetch_all(pool)
        .await?;
        
        Ok(users)
    }

    // List users by role with pagination
    pub async fn list_by_role(
        pool: &PgPool, 
        role: UserRole,
        limit: i64,
        offset: i64
    ) -> Result<Vec<User>, DatabaseError> {
        let users = sqlx::query_as!(
            User,
            r#"
            SELECT 
                id, email, password_hash, first_name, last_name, 
                role as "role: _", status as "status: _", 
                company_id, department, job_title, profile_image_url, phone_number,
                created_at, updated_at, last_login_at
            FROM users
            WHERE role = $1
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#,
            role as UserRole,
            limit,
            offset
        )
        .fetch_all(pool)
        .await?;
        
        Ok(users)
    }

    // Update password
    pub async fn update_password(
        pool: &PgPool,
        id: Uuid,
        password: SecretBox<String>
    ) -> Result<(), DatabaseError> {
        let password_hash = Self::hash_password(password.expose_secret())?;

        let result = sqlx::query!(
            "UPDATE users SET password_hash = $1 WHERE id = $2",
            password_hash,
            id
        )
        .execute(pool)
        .await?;
        
        if result.rows_affected() == 0 {
            return Err(DatabaseError::NotFound);
        }
        
        Ok(())
    }

    // Update last login timestamp
    pub async fn update_last_login(
        pool: &PgPool,
        id: Uuid
    ) -> Result<(), DatabaseError> {
        let now = OffsetDateTime::now_utc();
        
        let result = sqlx::query!(
            "UPDATE users SET last_login_at = $1 WHERE id = $2",
            now,
            id
        )
        .execute(pool)
        .await?;
        
        if result.rows_affected() == 0 {
            return Err(DatabaseError::NotFound);
        }
        
        Ok(())
    }

    // Helper method for transactional operations
    async fn find_by_id_tx(
        tx: &mut Transaction<'_, Postgres>,
        id: Uuid
    ) -> Result<User, DatabaseError> {
        let user = sqlx::query_as!(
            User,
            r#"
            SELECT
                id, email, password_hash, first_name, last_name,
                role as "role: _", status as "status: _",
                company_id, department, job_title, profile_image_url, phone_number,
                created_at, updated_at, last_login_at
            FROM users
            WHERE id = $1
            "#,
            id
        )
        .fetch_optional(&mut **tx)
        .await?;

        user.ok_or(DatabaseError::NotFound)
    }
}

// Helper implementation for UpdateUser
impl UpdateUser {
    fn is_empty(&self) -> bool {
        self.first_name.is_none() &&
        self.last_name.is_none() &&
        self.department.is_none() &&
        self.job_title.is_none() &&
        self.profile_image_url.is_none() &&
        self.phone_number.is_none() &&
        self.status.is_none() &&
        self.company_id.is_none()
    }
    
    fn only_has_first_name(&self) -> bool {
        self.first_name.is_some() &&
        self.last_name.is_none() &&
        self.department.is_none() &&
        self.job_title.is_none() &&
        self.profile_image_url.is_none() &&
        self.phone_number.is_none() &&
        self.status.is_none() &&
        self.company_id.is_none()
    }
}

// Display implementation for UserStatus
impl std::fmt::Display for UserStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            UserStatus::Active => write!(f, "active"),
            UserStatus::Inactive => write!(f, "inactive"),
            UserStatus::Pending => write!(f, "pending"),
            UserStatus::Suspended => write!(f, "suspended"),
        }
    }
} 