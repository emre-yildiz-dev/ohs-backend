// Explicitly import all types without UserRole
use crate::db::models::{NewUser, NewUserProfile, NewUserTenantContextRole, UpdateUser, UpdateUserProfile, 
    UpdateUserTenantContextRole, User, UserProfile, UserTenantContextRole, UserStatus};

// Import the UserRole type directly from the crate to avoid ambiguity
use secrecy::{ExposeSecret, SecretBox};
use sqlx::{Error, PgPool, Postgres, Transaction};
use uuid::Uuid;

// TODO: Replace with your actual password hashing utility
async fn hash_password_placeholder(password: &str) -> Result<String, String> {
    Ok(format!("hashed_{}", password))
}

pub struct UserRepository;

impl UserRepository {
    // User specific functions
    #[allow(unused)]
    pub async fn create_user(
        tx: &mut Transaction<'_, Postgres>,
        new_user_data: &NewUser,
    ) -> Result<User, Error> {
        let hashed_password = hash_password_placeholder(new_user_data.password.expose_secret())
            .await
            .map_err(|e| Error::Protocol(format!("Password hashing failed: {}", e).into()))?;

        // Query database and get raw fields, excluding the role which doesn't exist in the database
        let result = sqlx::query_as!(
            User,
            r#"
            INSERT INTO users (tenant_id, email, password_hash, status)
            VALUES ($1, $2, $3, $4::user_status)
            RETURNING id, tenant_id, company_id, email, password_hash, status AS "status: UserStatus", created_at, updated_at
            "#,
            new_user_data.tenant_id,
            new_user_data.email.to_lowercase(),
            hashed_password,
            UserStatus::Pending as _
        )
        .fetch_one(&mut **tx)
        .await?;

        // Manually construct the User struct with the role from the new_user_data
        let user = User {
            id: result.id,
            tenant_id: result.tenant_id,
            company_id: result.company_id,
            email: result.email,
            password_hash: result.password_hash,
            status: result.status,
            created_at: result.created_at,
            updated_at: result.updated_at,
        };

        Ok(user)
    }

    #[allow(unused)]
    pub async fn get_user_by_id(pool: &PgPool, user_id: Uuid) -> Result<Option<User>, Error> {
        let result = sqlx::query!(
            r#"
            SELECT id, tenant_id, company_id, email, password_hash, status AS "status: UserStatus", created_at, updated_at
            FROM users
            WHERE id = $1
            "#,
            user_id
        )
        .fetch_optional(pool)
        .await?;

        if let Some(user_data) = result {
            // Manually construct the User with a default role or fetch from user_tenant_context_roles
            let user = User {
                id: user_data.id,
                tenant_id: user_data.tenant_id,
                company_id: user_data.company_id,
                email: user_data.email,
                password_hash: user_data.password_hash,
                status: user_data.status,
                created_at: user_data.created_at,
                updated_at: user_data.updated_at,
            };
            Ok(Some(user))
        } else {
            Ok(None)
        }
    }

    #[allow(unused)]
    pub async fn get_user_by_email(pool: &PgPool, email: &str) -> Result<Option<User>, Error> {
        let result = sqlx::query!(
            r#"
            SELECT id, tenant_id, company_id, email, password_hash, status AS "status: UserStatus", created_at, updated_at
            FROM users
            WHERE email = $1
            "#,
            email.to_lowercase()
        )
        .fetch_optional(pool)
        .await?;

        if let Some(user_data) = result {
            // Manually construct the User with a default role or fetch from user_tenant_context_roles
            let user = User {
                id: user_data.id,
                tenant_id: user_data.tenant_id,
                company_id: user_data.company_id,
                email: user_data.email,
                password_hash: user_data.password_hash,
                status: user_data.status,
                created_at: user_data.created_at,
                updated_at: user_data.updated_at,
            };
            Ok(Some(user))
        } else {
            Ok(None)
        }
    }

    #[allow(unused)]
    pub async fn update_user(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        update_data: &UpdateUser,
    ) -> Result<User, Error> {
        let result = sqlx::query!(
            r#"
            UPDATE users
            SET 
                status = COALESCE($1::user_status, status),
                company_id = COALESCE($2, company_id),
                updated_at = NOW()
            WHERE id = $3
            RETURNING id, tenant_id, company_id, email, password_hash, status AS "status: UserStatus", created_at, updated_at
            "#,
            update_data.status as _,
            update_data.company_id,
            user_id
        )
        .fetch_one(&mut **tx)
        .await?;

        // Manually construct the User with a default role or fetch from user_tenant_context_roles
        let user = User {
            id: result.id,
            tenant_id: result.tenant_id,
            company_id: result.company_id,
            email: result.email,
            password_hash: result.password_hash,
            status: result.status,
            created_at: result.created_at,
            updated_at: result.updated_at,
        };

        Ok(user)
    }
    
    #[allow(unused)]
    pub async fn update_user_password(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        new_password: &SecretBox<String>,
    ) -> Result<(), Error> {
        let hashed_password = hash_password_placeholder(new_password.expose_secret())
            .await
            .map_err(|e| Error::Protocol(format!("Password hashing failed: {}",e).into()))?;

        sqlx::query!(
            r#"
            UPDATE users
            SET password_hash = $1, updated_at = NOW()
            WHERE id = $2
            "#,
            hashed_password,
            user_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[allow(unused)]
    pub async fn delete_user(tx: &mut Transaction<'_, Postgres>, user_id: Uuid) -> Result<(), Error> {
        sqlx::query!("DELETE FROM users WHERE id = $1", user_id)
            .execute(&mut **tx)
            .await?;
        Ok(())
    }

    // UserProfile specific functions
    #[allow(unused)]
    pub async fn create_user_profile(
        tx: &mut Transaction<'_, Postgres>,
        profile_data: &NewUserProfile,
    ) -> Result<UserProfile, Error> {
        sqlx::query_as!(
            UserProfile,
            r#"
            INSERT INTO user_profiles (user_id, first_name, last_name, date_of_birth, gender, phone_number, profile_picture_url, company_id, department, job_title, address, city, state, zip_code, country)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
            RETURNING user_id, first_name, last_name, date_of_birth, gender, phone_number, profile_picture_url, company_id, department, job_title, address, city, state, zip_code, country, created_at, updated_at
            "#,
            profile_data.user_id,
            profile_data.first_name,
            profile_data.last_name,
            profile_data.date_of_birth,
            profile_data.gender,
            profile_data.phone_number,
            profile_data.profile_picture_url,
            profile_data.company_id,
            profile_data.department,
            profile_data.job_title,
            profile_data.address,
            profile_data.city,
            profile_data.state,
            profile_data.zip_code,
            profile_data.country
        )
        .fetch_one(&mut **tx)
        .await
    }

    #[allow(unused)]
    pub async fn get_user_profile_by_user_id(pool: &PgPool, user_id: Uuid) -> Result<Option<UserProfile>, Error> {
        sqlx::query_as!(
            UserProfile,
            r#"
            SELECT user_id, first_name, last_name, date_of_birth, gender, phone_number, profile_picture_url, company_id, department, job_title, address, city, state, zip_code, country, created_at, updated_at
            FROM user_profiles
            WHERE user_id = $1
            "#,
            user_id
        )
        .fetch_optional(pool)
        .await
    }

    #[allow(unused)]
    pub async fn update_user_profile(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        profile_data: &UpdateUserProfile,
    ) -> Result<UserProfile, Error> {
        sqlx::query_as!(
            UserProfile,
            r#"
            UPDATE user_profiles
            SET 
                first_name = COALESCE($1, first_name),
                last_name = COALESCE($2, last_name),
                date_of_birth = COALESCE($3, date_of_birth),
                gender = COALESCE($4, gender),
                phone_number = COALESCE($5, phone_number),
                profile_picture_url = COALESCE($6, profile_picture_url),
                company_id = COALESCE($7, company_id),
                department = COALESCE($8, department),
                job_title = COALESCE($9, job_title),
                address = COALESCE($10, address),
                city = COALESCE($11, city),
                state = COALESCE($12, state),
                zip_code = COALESCE($13, zip_code),
                country = COALESCE($14, country),
                updated_at = NOW()
            WHERE user_id = $15
            RETURNING user_id, first_name, last_name, date_of_birth, gender, phone_number, profile_picture_url, company_id, department, job_title, address, city, state, zip_code, country, created_at, updated_at
            "#,
            profile_data.first_name,
            profile_data.last_name,
            profile_data.date_of_birth,
            profile_data.gender,
            profile_data.phone_number,
            profile_data.profile_picture_url,
            profile_data.company_id,
            profile_data.department,
            profile_data.job_title,
            profile_data.address,
            profile_data.city,
            profile_data.state,
            profile_data.zip_code,
            profile_data.country,
            user_id
        )
        .fetch_one(&mut **tx)
        .await
    }

    // UserTenantContextRole specific functions
    #[allow(unused)]
    pub async fn create_user_tenant_context_role(
        tx: &mut Transaction<'_, Postgres>,
        role_data: &NewUserTenantContextRole,
    ) -> Result<UserTenantContextRole, Error> {
        sqlx::query_as!(
            UserTenantContextRole,
            r#"
            INSERT INTO user_tenant_context_roles (user_id, role, tenant_id, company_id)
            VALUES ($1, $2::user_role, $3, $4)
            RETURNING id, user_id, role AS "role: _", tenant_id, company_id, created_at
            "#,
            role_data.user_id,
            // We need to cast to the correct enum type used by the DB
            role_data.role as _,
            role_data.tenant_id,
            role_data.company_id
        )
        .fetch_one(&mut **tx)
        .await
    }

    #[allow(unused)]
    pub async fn get_user_tenant_context_roles_by_user_id(pool: &PgPool, user_id: Uuid) -> Result<Vec<UserTenantContextRole>, Error> {
        sqlx::query_as!(
            UserTenantContextRole,
            r#"
            SELECT id, user_id, role AS "role: _", tenant_id, company_id, created_at
            FROM user_tenant_context_roles
            WHERE user_id = $1
            "#,
            user_id
        )
        .fetch_all(pool)
        .await
    }

    #[allow(unused)]
    pub async fn update_user_tenant_context_role(
        tx: &mut Transaction<'_, Postgres>,
        role_id: Uuid,
        role_data: &UpdateUserTenantContextRole,
    ) -> Result<UserTenantContextRole, Error> {
         sqlx::query_as!(
            UserTenantContextRole,
            r#"
            UPDATE user_tenant_context_roles
            SET 
                role = COALESCE($1::user_role, role),
                tenant_id = COALESCE($2, tenant_id),
                company_id = COALESCE($3, company_id)
            WHERE id = $4
            RETURNING id, user_id, role AS "role: _", tenant_id, company_id, created_at
            "#,
            role_data.role.clone().unwrap() as _,
            role_data.tenant_id,
            role_data.company_id,
            role_id
        )
        .fetch_one(&mut **tx)
        .await
    }

    #[allow(unused)]
    pub async fn delete_user_tenant_context_role(tx: &mut Transaction<'_, Postgres>, role_id: Uuid) -> Result<(), Error> {
        sqlx::query!("DELETE FROM user_tenant_context_roles WHERE id = $1", role_id)
            .execute(&mut **tx)
            .await?;
        Ok(())
    }
}
