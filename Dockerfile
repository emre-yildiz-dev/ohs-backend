# === Builder Stage ===
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
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/src/app/ohs-backend/target \
    cargo build --release && \
    rm src/*.rs

# Copy the source code
COPY src ./src

# Build for release
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/src/app/ohs-backend/target \
    cargo build --release

# === Runtime Stage ===
FROM debian:bookworm-stable-slim

# Runtime dependencies
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

# Create a non-root user
RUN groupadd -r app && useradd -r -g app app

WORKDIR /app

# Copy the binary from builder stage
COPY --from=builder /usr/src/app/ohs-backend/target/release/ohs-backend /app/ohs-backend

# Set ownership
RUN chown app:app /app/ohs-backend
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