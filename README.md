# OHS Backend

Multi-tenant Occupational Health and Safety Backend Application built with Rust, Axum, and PostgreSQL.

## Features

- Multi-tenant architecture for OHS management
- User management with role-based access control
- Appointment scheduling and management
- Training session coordination
- Safety reporting and incident tracking
- Real-time notifications
- WebSocket support for live updates

## Prerequisites

- Rust 1.77.0+
- Docker and Docker Compose
- PostgreSQL 17+
- Redis 8+

## Setup

### 1. Clone the repository

```bash
git clone https://github.com/yourusername/ohs-backend.git
cd ohs-backend
```

### 2. Configure Environment

Before running the application, you need to set up your environment variables.
- If an `.env.example` file exists in the repository, copy it to a new file named `.env`:
  ```bash
  cp .env.example .env
  ```
- Otherwise, create a `.env` file manually.
- Edit the `.env` file to set the `DATABASE_URL` and other necessary configurations.
  - For local terminal development, `DATABASE_URL` should point to the PostgreSQL instance (e.g., `postgres://user:pass@localhost:5432/dbname`). The `./setup-db.sh` script (described below) assists in this.
  - When using Docker Compose for the entire stack, the application service within Docker Compose will typically get its `DATABASE_URL` from environment variables defined in the `docker-compose.yml` file, pointing to the PostgreSQL service name (e.g., `postgres://user:pass@db_service_name:5432/dbname`).

## Running the Application

You have two main options to run the application:

### Option 1: Locally via Terminal (for development)

#### a. Setup the Database

We use SQLx for database access and migrations. The provided script helps set up a PostgreSQL database using Docker and applies migrations:

```bash
./setup-db.sh
```

This script will typically:
- Start a PostgreSQL container using Docker Compose (for the database service).
- Install the SQLx CLI if not already installed.
- Create a `.env` file if it doesn't exist and may populate `DATABASE_URL`.
- Run database migrations to set up the schema.

*Alternatively, if you prefer to manage your PostgreSQL instance manually:*
1. Ensure your PostgreSQL server is running and accessible.
2. Set the `DATABASE_URL` in your `.env` file accordingly.
3. Install SQLx CLI if needed: `cargo install sqlx-cli --no-default-features --features native-tls,postgres`.
4. Run migrations: `sqlx migrate run`.

#### b. Prepare SQLx for Compile-Time Verification

This step checks your SQL queries against the database schema at compile time. It's recommended to run this after setting up the database and running migrations:

```bash
cargo sqlx prepare
```

#### c. Build and Run the Application

```bash
cargo build
cargo run
```

Or for development with auto-reloading on code changes:

```bash
cargo watch -x run
```

The application will be available at `http://localhost:8000` (or as configured by `SERVER_HOST` and `SERVER_PORT` environment variables).

### Option 2: Using Docker Compose (for the entire stack)

This method runs the application along with its dependencies like PostgreSQL and Redis, all containerized.

1.  **Ensure Docker and Docker Compose are installed.**

2.  **Start all services**:
    After the database is set up and migrated by the script above, start all services (including the application, Redis, etc.) defined in your `docker-compose.yml` file:
    ```bash
    docker-compose up -d
    ```
    This command will build the necessary images (if not already built) and start all services in detached mode. The application will be accessible according to its configuration within the Docker Compose setup (e.g., mapped ports).

## Database Migrations

### Create a new migration

```bash
sqlx migrate add <migration_name>
```

This creates a new file in the `migrations` directory.

### Apply migrations

```bash
sqlx migrate run
```

### Revert the last migration

```bash
sqlx migrate revert
```

## Environment Variables

The application uses the following environment variables:

- `SERVER_HOST`: Host to bind the server to (default: `0.0.0.0`)
- `SERVER_PORT`: Port to listen on (default: `8000`)
- `DATABASE_URL`: PostgreSQL connection string
- `DATABASE_MAX_CONNECTIONS`: Maximum number of database connections (default: `10`)
- `DATABASE_MIN_CONNECTIONS`: Minimum number of database connections (default: `2`)
- `REDIS_URL`: Redis connection string
- `APP_NAME`: Application name (default: `"OHS Backend"`)
- `APP_ENVIRONMENT`: Environment (`development`, `staging`, `production`)
- `STATIC_DIR`: Directory for static files (default: `static`)
- `TEMPLATES_DIR`: Directory for templates (default: `templates`)
- `RUST_LOG`: Logging level (default: `debug`)

## License

This project is licensed under the AKO License - see the LICENSE file for details.
