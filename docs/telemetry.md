# OpenTelemetry Integration

This document describes the OpenTelemetry integration in the OHS Backend application, providing comprehensive observability through distributed tracing, metrics, and structured logging.

## Features

- **Distributed Tracing**: Track requests across services with OpenTelemetry spans
- **Metrics Collection**: HTTP request metrics, response times, and custom business metrics
- **Structured Logging**: Enhanced logging with trace correlation
- **OTLP Export**: Support for OpenTelemetry Protocol (OTLP) exporters
- **Development Fallback**: Console/stdout exporters for local development
- **Graceful Shutdown**: Proper cleanup of telemetry providers

## Configuration

The telemetry system can be configured through environment variables:

### Core Configuration

```env
# OpenTelemetry Collector endpoint (optional)
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317

# Service identification
OTEL_SERVICE_NAME=ohs-backend
OTEL_SERVICE_VERSION=0.1.0
DEPLOYMENT_ENVIRONMENT=development
```

### Feature Toggles

```env
# Enable/disable telemetry features
OTEL_TRACES_ENABLED=true
OTEL_METRICS_ENABLED=true
OTEL_LOGS_ENABLED=true
```

### Sampling Configuration

```env
# Trace sampling configuration
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=1.0
```

## Usage

### Basic Setup

The telemetry system is automatically initialized in `main.rs`:

```rust
// Initialize OpenTelemetry
let telemetry_handles = telemetry::init_telemetry(None).await
    .context("Failed to initialize telemetry")?;

// ... application code ...

// Graceful shutdown
telemetry_handles.shutdown().await
    .context("Failed to shutdown telemetry")?;
```

### Custom Configuration

You can provide custom configuration:

```rust
use crate::telemetry::{TelemetryConfig, init_telemetry};

let config = TelemetryConfig {
    service_name: "my-service".to_string(),
    environment: "production".to_string(),
    otlp_endpoint: Some("http://jaeger:4317".to_string()),
    enable_tracing: true,
    enable_metrics: true,
    enable_logging: true,
    sample_ratio: 0.1, // 10% sampling
    export_timeout: Duration::from_secs(10),
    export_batch_size: 256,
};

let handles = init_telemetry(Some(config)).await?;
```

### Creating Custom Spans

Use the convenience macro for creating spans:

```rust
use crate::traced_span;
use crate::telemetry::get_tracer;

let tracer = get_tracer("my-component");

// Simple span
let span = traced_span!(tracer, "operation_name");

// Span with attributes
let span = traced_span!(
    tracer, 
    "database_query",
    "db.statement" => "SELECT * FROM users",
    "db.operation" => "select",
    "user.id" => user_id
);
```

### Custom Metrics

Create and use custom metrics:

```rust
use crate::telemetry::get_meter;
use opentelemetry::KeyValue;

let meter = get_meter("business-metrics");

// Counter
let login_counter = meter
    .u64_counter("user_logins_total")
    .with_description("Total number of user logins")
    .build();

login_counter.add(1, &[
    KeyValue::new("user_type", "admin"),
    KeyValue::new("success", "true"),
]);

// Histogram
let processing_time = meter
    .f64_histogram("processing_duration_seconds")
    .with_description("Time spent processing requests")
    .build();

processing_time.record(0.125, &[
    KeyValue::new("operation", "create_user"),
]);

// Gauge (using up_down_counter for gauge-like behavior)
let active_connections = meter
    .i64_up_down_counter("active_connections")
    .with_description("Number of active connections")
    .build();

active_connections.add(1, &[]);
```

### Structured Logging with Trace Correlation

```rust
use tracing::{info, error, warn};
use opentelemetry::trace::{TraceContextExt, Span};

// Logs will automatically include trace context when inside a span
let tracer = get_tracer("my-service");
let span = tracer.start("user_registration");
let _guard = span.clone();

info!(
    user_id = %user.id,
    email = %user.email,
    "User registration completed successfully"
);

// Error logging with context
if let Err(e) = some_operation().await {
    error!(
        error = %e,
        operation = "user_registration",
        "Failed to register user"
    );
}
```

## HTTP Middleware

The application automatically includes observability middleware that:

- Creates spans for each HTTP request
- Records HTTP metrics (request count, duration, status codes)
- Adds request attributes to spans
- Correlates logs with traces

The middleware is automatically applied to all routes in `app.rs`.

## Exporters

### OTLP Exporter (Production)

When `OTEL_EXPORTER_OTLP_ENDPOINT` is configured, telemetry data is exported via OTLP to:
- Jaeger (for tracing)
- Prometheus (for metrics via OTLP)
- Elasticsearch/Loki (for logs)

### Stdout Exporter (Development)

When no OTLP endpoint is configured, telemetry data is exported to stdout for development and debugging.

## Health Checks

The `/health` endpoint includes telemetry system status:

```json
{
  "status": "ok",
  "timestamp": "2024-01-01T00:00:00Z",
  "version": "0.1.0",
  "services": {
    "database": "healthy",
    "telemetry": {
      "tracer_provider": true,
      "meter_provider": true,
      "logger_provider": true
    }
  }
}
```

## Running with OpenTelemetry Collector

### Docker Compose Example

```yaml
version: '3.8'
services:
  # Your application
  ohs-backend:
    build: .
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
      - OTEL_SERVICE_NAME=ohs-backend
      - DEPLOYMENT_ENVIRONMENT=development
    depends_on:
      - otel-collector

  # OpenTelemetry Collector
  otel-collector:
    image: otel/opentelemetry-collector:latest
    command: ["--config=/etc/otel-collector-config.yaml"]
    volumes:
      - ./otel-collector-config.yaml:/etc/otel-collector-config.yaml
    ports:
      - "4317:4317"   # OTLP gRPC receiver
      - "4318:4318"   # OTLP HTTP receiver
    depends_on:
      - jaeger

  # Jaeger for tracing
  jaeger:
    image: jaegertracing/all-in-one:latest
    ports:
      - "16686:16686"
      - "14250:14250"
    environment:
      - COLLECTOR_OTLP_ENABLED=true
```

### Collector Configuration Example

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:

exporters:
  jaeger:
    endpoint: jaeger:14250
    tls:
      insecure: true
  
  prometheus:
    endpoint: "0.0.0.0:8889"

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [jaeger]
    
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheus]
```

## Best Practices

1. **Use Semantic Conventions**: Follow OpenTelemetry semantic conventions for attribute names
2. **Instrument at Boundaries**: Add spans at service boundaries, database calls, and external API calls
3. **High-Cardinality Attributes**: Be careful with high-cardinality attributes in metrics
4. **Sampling**: Use appropriate sampling rates for production environments
5. **Error Handling**: Always set span status appropriately for errors
6. **Resource Attributes**: Include relevant resource attributes for service identification

## Troubleshooting

### No Telemetry Data

1. Check if the OTLP endpoint is reachable
2. Verify environment variables are set correctly
3. Check application logs for telemetry initialization errors
4. Ensure the OpenTelemetry Collector is running and configured correctly

### High Resource Usage

1. Reduce sampling rate with `OTEL_TRACES_SAMPLER_ARG`
2. Increase batch export intervals
3. Reduce the number of high-cardinality metric attributes

### Compilation Issues

Ensure all OpenTelemetry dependencies are compatible versions:

```toml
[dependencies]
opentelemetry = "0.27"
opentelemetry-sdk = "0.27"
opentelemetry-otlp = "0.27"
opentelemetry-semantic-conventions = "0.27"
opentelemetry-appender-tracing = "0.27"
opentelemetry-stdout = "0.27"
``` 