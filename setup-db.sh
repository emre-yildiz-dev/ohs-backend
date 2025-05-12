#!/bin/bash
set -e

# Start PostgreSQL container if not running
if ! docker ps | grep -q ohs_postgres; then
    echo "Starting PostgreSQL container..."
    docker-compose up -d postgres
    
    # Wait for PostgreSQL to be ready
    echo "Waiting for PostgreSQL to be ready..."
    while ! docker exec ohs_postgres pg_isready -U user -d ohs_db > /dev/null 2>&1; do
        echo -n "."
        sleep 1
    done
    echo "PostgreSQL is ready!"
else
    echo "PostgreSQL container is already running"
fi

# Install sqlx-cli if not already installed
if ! command -v sqlx &> /dev/null; then
    echo "Installing sqlx-cli..."
    cargo install sqlx-cli --no-default-features --features native-tls,postgres
fi

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    echo "Creating .env file..."
    cat > .env << EOL
SERVER_HOST=0.0.0.0
SERVER_PORT=8000

DATABASE_URL=postgresql://user:password@localhost:5432/ohs_db
DATABASE_MAX_CONNECTIONS=10
DATABASE_MIN_CONNECTIONS=2

REDIS_URL=redis://localhost:6379

APP_NAME="OHS Backend"
APP_ENVIRONMENT=development
STATIC_DIR=static
TEMPLATES_DIR=templates

RUST_LOG=debug
EOL
    echo ".env file created"
else
    echo ".env file already exists"
fi

# Run migrations
echo "Running database migrations..."
sqlx database create
sqlx migrate run

echo "Database setup complete!" 