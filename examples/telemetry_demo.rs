use anyhow::Result;
use ohs_backend::telemetry::{init_telemetry, get_tracer, get_meter, TelemetryConfig};
use opentelemetry::{trace::{Tracer, Span}, KeyValue};
use std::time::Duration;
use tracing::{info, error};

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize telemetry with custom configuration
    let config = TelemetryConfig {
        service_name: "telemetry-demo".to_string(),
        service_version: "1.0.0".to_string(),
        environment: "demo".to_string(),
        otlp_endpoint: None, // Use console output for demo
        enable_tracing: true,
        enable_metrics: true,
        export_timeout: Duration::from_secs(10),
    };

    let telemetry_handles = init_telemetry(Some(config)).await?;

    // Demonstrate tracing
    demonstrate_tracing().await;

    // Demonstrate metrics
    demonstrate_metrics();

    // Demonstrate structured logging
    demonstrate_logging().await;

    // Shutdown telemetry
    telemetry_handles.shutdown().await?;

    Ok(())
}

async fn demonstrate_tracing() {
    info!("=== Demonstrating OpenTelemetry Tracing ===");
    
    let tracer = get_tracer("demo-tracer");
    
    // Create a parent span
    let mut parent_span = tracer
        .span_builder("demo_operation")
        .start(&tracer);
    
    parent_span.set_attribute(KeyValue::new("operation.type", "demo"));
    parent_span.set_attribute(KeyValue::new("user.id", "12345"));
    
    // Simulate some work
    tokio::time::sleep(Duration::from_millis(100)).await;
    
    // Create a child span
    let mut child_span = tracer
        .span_builder("database_query")
        .start(&tracer);
    
    child_span.set_attribute(KeyValue::new("db.statement", "SELECT * FROM users"));
    child_span.set_attribute(KeyValue::new("db.operation", "select"));
    
    // Simulate database work
    tokio::time::sleep(Duration::from_millis(50)).await;
    
    child_span.end();
    parent_span.end();
    
    info!("Tracing demonstration completed");
}

fn demonstrate_metrics() {
    info!("=== Demonstrating OpenTelemetry Metrics ===");
    
    let meter = get_meter("demo-meter");
    
    // Create a counter
    let request_counter = meter
        .u64_counter("demo_requests_total")
        .with_description("Total number of demo requests")
        .build();
    
    // Create a histogram
    let response_time = meter
        .f64_histogram("demo_response_time_seconds")
        .with_description("Demo response time in seconds")
        .build();
    
    // Record some metrics
    for i in 1..=5 {
        let labels = vec![
            KeyValue::new("method", "GET"),
            KeyValue::new("status", "200"),
            KeyValue::new("iteration", i.to_string()),
        ];
        
        request_counter.add(1, &labels);
        response_time.record(0.1 * i as f64, &labels);
    }
    
    info!("Metrics demonstration completed");
}

async fn demonstrate_logging() {
    info!("=== Demonstrating Structured Logging ===");
    
    // Structured logging with context
    info!(
        user_id = "12345",
        operation = "user_login",
        success = true,
        "User login successful"
    );
    
    // Error logging
    error!(
        error = "Database connection failed",
        retry_count = 3,
        "Failed to connect to database after retries"
    );
    
    // Logging with custom fields
    info!(
        request_id = %uuid::Uuid::now_v7(),
        endpoint = "/api/users",
        method = "POST",
        response_time_ms = 150,
        "API request processed"
    );
    
    info!("Logging demonstration completed");
} 