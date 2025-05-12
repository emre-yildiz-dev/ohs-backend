#!/bin/bash
set -e

# Make sure the PostgreSQL container is running
if ! docker ps | grep -q ohs_postgres; then
    echo "PostgreSQL container is not running. Starting it..."
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

# Test direct connection to PostgreSQL
echo "Testing direct connection to PostgreSQL..."
docker exec ohs_postgres psql -U user -d ohs_db -c "SELECT version();"

# Test connection using sqlx-cli
if command -v sqlx &> /dev/null; then
    echo "Testing connection using sqlx-cli..."
    export DATABASE_URL="postgresql://user:password@localhost:5432/ohs_db"
    sqlx database list
else
    echo "sqlx-cli is not installed. Skipping sqlx-cli connection test."
    echo "You can install it with: cargo install sqlx-cli"
fi

# Test connection using app health check endpoint (if the app is running)
if nc -z localhost 8000 2>/dev/null; then
    echo "Testing connection through application health check..."
    curl -s http://localhost:8000/health | jq
else
    echo "Application is not running. Skipping health check test."
    echo "You can start the application with: cargo run"
fi

echo "Done!" 