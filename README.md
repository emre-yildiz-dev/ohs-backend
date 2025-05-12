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

### 2. Setup the database

We use SQLx for database access and migrations. Run the setup script to start the PostgreSQL container and apply migrations:

```bash
./setup-db.sh
```

This script will:
- Start a PostgreSQL container using Docker Compose
- Install the SQLx CLI if not already installed
- Create a `.env` file if it doesn't exist
- Run database migrations

### 3. Build and run the application

```bash
cargo build
cargo run
```

Or for development with auto-reloading:

```bash
cargo watch -x run
```

The application will be available at `http://localhost:8000`.

### 4. Run with Docker Compose (optional)

To run the entire stack (including Redis, PostgreSQL, and object storage):

```bash
docker-compose up -d
```

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

This project is licensed under the MIT License - see the LICENSE file for details.
