use axum::{
    extract::{Request, MatchedPath},
    http::{HeaderMap, Method, Uri},
    middleware::Next,
    response::Response,
};
use opentelemetry::{
    global,
    trace::{Span, SpanKind, Status, Tracer},
    KeyValue,
};
use std::time::Instant;
use tracing::{info_span, Instrument};

/// OpenTelemetry tracing middleware for HTTP requests
#[allow(dead_code)]
pub async fn otel_tracing_middleware(
    request: Request,
    next: Next,
) -> Response {
    let tracer = global::tracer("http-server");
    
    let method = request.method().clone();
    let uri = request.uri().clone();
    let headers = request.headers().clone();
    
    // Extract route pattern if available
    let route = request
        .extensions()
        .get::<MatchedPath>()
        .map(|path| path.as_str())
        .unwrap_or("unknown")
        .to_string();

    // Create OpenTelemetry span
    let mut span = tracer
        .span_builder(format!("{} {}", method, route))
        .with_kind(SpanKind::Server)
        .start(&tracer);

    // Set standard HTTP attributes
    span.set_attribute(KeyValue::new("http.method", method.to_string()));
    span.set_attribute(KeyValue::new("http.url", uri.to_string()));
    span.set_attribute(KeyValue::new("http.route", route.clone()));
    span.set_attribute(KeyValue::new("http.scheme", uri.scheme_str().unwrap_or("http").to_string()));
    
    if let Some(host) = uri.host() {
        span.set_attribute(KeyValue::new("http.host", host.to_string()));
    }
    
    if let Some(user_agent) = headers.get("user-agent") {
        if let Ok(ua) = user_agent.to_str() {
            span.set_attribute(KeyValue::new("http.user_agent", ua.to_string()));
        }
    }

    let start_time = Instant::now();
    
    // Create tracing span for structured logging
    let tracing_span = info_span!(
        "http_request",
        method = %method,
        uri = %uri,
        route = %route,
    );
    
    // Execute the request within the span context
    let response = next.run(request).instrument(tracing_span).await;

    let duration = start_time.elapsed();
    let status_code = response.status().as_u16();

    // Set response attributes
    span.set_attribute(KeyValue::new("http.status_code", status_code as i64));
    span.set_attribute(KeyValue::new("http.response_time_ms", duration.as_millis() as i64));

    // Set span status based on HTTP status code
    if status_code >= 400 {
        if status_code >= 500 {
            span.set_status(Status::Error {
                description: format!("HTTP {}", status_code).into(),
            });
        } else {
            span.set_status(Status::Ok);
        }
    } else {
        span.set_status(Status::Ok);
    }

    // End the span
    span.end();

    response
}

/// Metrics middleware for collecting HTTP metrics
#[allow(dead_code)]
pub async fn metrics_middleware(
    request: Request,
    next: Next,
) -> Response {
    let method = request.method().clone();
    
    // Extract route pattern if available
    let route = request
        .extensions()
        .get::<MatchedPath>()
        .map(|path| path.as_str())
        .unwrap_or("unknown")
        .to_string();

    let start_time = Instant::now();
    let meter = crate::telemetry::get_meter("http-server");
    
    // Get metrics instruments
    let request_counter = meter
        .u64_counter("http_requests_total")
        .with_description("Total number of HTTP requests")
        .build();
        
    let request_duration = meter
        .f64_histogram("http_request_duration_seconds")
        .with_description("HTTP request duration in seconds")
        .build();

    // Execute the request
    let response = next.run(request).await;
    
    let duration = start_time.elapsed();
    let status_code = response.status().as_u16();
    
    // Record metrics
    let labels = vec![
        KeyValue::new("method", method.to_string()),
        KeyValue::new("route", route),
        KeyValue::new("status_code", status_code.to_string()),
    ];
    
    request_counter.add(1, &labels);
    request_duration.record(duration.as_secs_f64(), &labels);

    response
}

/// Combined middleware that includes both tracing and metrics
pub async fn observability_middleware(
    matched_path: MatchedPath,
    request: Request,
    next: Next,
) -> Response {
    let method = request.method().clone();
    let uri = request.uri().clone();
    let headers = request.headers().clone();
    let start_time = Instant::now();
    
    // Use the matched path directly
    let route = matched_path.as_str();

    // OpenTelemetry tracing
    let tracer = global::tracer("http-server");
    let mut span = tracer
        .span_builder(format!("{} {}", method, route))
        .with_kind(SpanKind::Server)
        .start(&tracer);

    // Set tracing attributes
    set_span_attributes(&mut span, &method, &uri, route, &headers);

    // Metrics setup
    let meter = crate::telemetry::get_meter("http-server");
    let request_counter = meter
        .u64_counter("http_requests_total")
        .with_description("Total number of HTTP requests")
        .build();
        
    let request_duration = meter
        .f64_histogram("http_request_duration_seconds")
        .with_description("HTTP request duration in seconds")
        .build();
    
    let tracing_span = info_span!(
        "http_request",
        method = %method,
        uri = %uri,
        route = %route,
        request_id = %uuid::Uuid::now_v7(),
    );
    
    // Execute the request
    let response = next.run(request).instrument(tracing_span).await;

    let duration = start_time.elapsed();
    let status_code = response.status().as_u16();

    // Update span with response data
    span.set_attribute(KeyValue::new("http.status_code", status_code as i64));
    span.set_attribute(KeyValue::new("http.response_time_ms", duration.as_millis() as i64));

    // Set span status
    if status_code >= 500 {
        span.set_status(Status::Error {
            description: format!("HTTP {}", status_code).into(),
        });
    } else {
        span.set_status(Status::Ok);
    }

    // Record metrics
    let labels = vec![
        KeyValue::new("method", method.to_string()),
        KeyValue::new("route", route.to_string()),
        KeyValue::new("status_code", status_code.to_string()),
    ];
    
    request_counter.add(1, &labels);
    request_duration.record(duration.as_secs_f64(), &labels);

    span.end();
    response
}

/// Helper function to set span attributes
fn set_span_attributes(
    span: &mut impl Span,
    method: &Method,
    uri: &Uri,
    route: &str,
    headers: &HeaderMap,
) {
    span.set_attribute(KeyValue::new("http.method", method.to_string()));
    span.set_attribute(KeyValue::new("http.url", uri.to_string()));
    span.set_attribute(KeyValue::new("http.route", route.to_string()));
    span.set_attribute(KeyValue::new("http.scheme", uri.scheme_str().unwrap_or("http").to_string()));
    
    if let Some(host) = uri.host() {
        span.set_attribute(KeyValue::new("http.host", host.to_string()));
    }
    
    if let Some(user_agent) = headers.get("user-agent") {
        if let Ok(ua) = user_agent.to_str() {
            span.set_attribute(KeyValue::new("http.user_agent", ua.to_string()));
        }
    }
    
    if let Some(forwarded_for) = headers.get("x-forwarded-for") {
        if let Ok(xff) = forwarded_for.to_str() {
            span.set_attribute(KeyValue::new("http.client_ip", xff.to_string()));
        }
    }
} 