FROM node:20-slim AS css-builder

# Set working directory
WORKDIR /app

# Copy package files
COPY package.json pnpm-lock.yaml* ./
COPY static ./static
COPY tailwind.config.js* postcss.config.js* ./

# Install pnpm and dependencies
RUN npm install -g pnpm && \
    pnpm install && \
    pnpm run build:css

FROM rust:1.86.0-slim-bookworm AS builder

# Create a new empty shell project
WORKDIR /usr/src/app
RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*

# Create a new empty shell project
RUN USER=root cargo new --bin ohs-backend
WORKDIR /usr/src/app/ohs-backend

# Copy our manifests
COPY Cargo.lock Cargo.toml ./

# Build only the dependencies to cache them
RUN cargo build --release && \
    rm src/*.rs

# Copy the source code, templates, migrations, and SQLx prepared queries
COPY src ./src
COPY templates ./templates
COPY migrations ./migrations
COPY .sqlx ./.sqlx

# Copy the compiled CSS from the css-builder stage
COPY --from=css-builder /app/static/css/main.css ./static/css/

# Build for release
RUN cargo build --release

# === Runtime Stage ===
FROM debian:bookworm-slim

# Runtime dependencies
RUN apt-get update && apt-get install -y ca-certificates curl && rm -rf /var/lib/apt/lists/*

# Create a non-root user
RUN groupadd -r app && useradd -r -g app app

WORKDIR /app

# Copy the binary from builder stage
COPY --from=builder /usr/src/app/ohs-backend/target/release/ohs-backend /app/ohs-backend
# Copy templates to runtime image
COPY --from=builder /usr/src/app/ohs-backend/templates /app/templates
# Copy static files including compiled CSS
COPY --from=builder /usr/src/app/ohs-backend/static /app/static
# Copy migrations folder to runtime image
COPY --from=builder /usr/src/app/ohs-backend/migrations /app/migrations

# Set ownership
RUN chown -R app:app /app
USER app

# Application metadata
LABEL org.opencontainers.image.title="OHS Backend"
LABEL org.opencontainers.image.description="Axum-based backend service"
LABEL org.opencontainers.image.version="1.0.0"

# Configure the application
ENV RUST_LOG=info
ENV LISTEN_ADDRESS=0.0.0.0:8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Expose the port
EXPOSE 8080

# Run the binary
CMD ["/app/ohs-backend"]