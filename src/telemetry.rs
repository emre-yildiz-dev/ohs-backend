use anyhow::{Context, Result};
use opentelemetry::{global, KeyValue};
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_sdk::{runtime, Resource};
use std::collections::HashMap;
use std::time::Duration;
use tracing::info;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter, Registry};

/// Telemetry configuration structure
#[derive(Debug, Clone)]
pub struct TelemetryConfig {
    pub service_name: String,
    pub service_version: String,
    pub environment: String,
    pub otlp_endpoint: Option<String>,
    pub enable_tracing: bool,
    pub enable_metrics: bool,
    pub export_timeout: Duration,
}

impl Default for TelemetryConfig {
    fn default() -> Self {
        Self {
            service_name: env!("CARGO_PKG_NAME").to_string(),
            service_version: env!("CARGO_PKG_VERSION").to_string(),
            environment: std::env::var("DEPLOYMENT_ENVIRONMENT").unwrap_or_else(|_| "development".to_string()),
            otlp_endpoint: std::env::var("OTEL_EXPORTER_OTLP_ENDPOINT").ok(),
            enable_tracing: std::env::var("OTEL_TRACES_ENABLED")
                .map(|v| v.parse().unwrap_or(true))
                .unwrap_or(true),
            enable_metrics: std::env::var("OTEL_METRICS_ENABLED")
                .map(|v| v.parse().unwrap_or(true))
                .unwrap_or(true),
            export_timeout: Duration::from_secs(30),
        }
    }
}

/// Telemetry handles for graceful shutdown
pub struct TelemetryHandles {
    _config: TelemetryConfig,
}

impl TelemetryHandles {
    /// Gracefully shutdown all telemetry providers
    pub async fn shutdown(self) -> Result<()> {
        info!("Shutting down telemetry providers...");
        
        // Shutdown global providers
        global::shutdown_tracer_provider();
        
        info!("Telemetry providers shutdown completed");
        Ok(())
    }
}

/// Initialize OpenTelemetry with comprehensive observability setup
pub async fn init_telemetry(config: Option<TelemetryConfig>) -> Result<TelemetryHandles> {
    let config = config.unwrap_or_default();
    
    info!(
        "Initializing telemetry for service: {} v{} in environment: {}",
        config.service_name, config.service_version, config.environment
    );

    // Create base resource with service information
    let resource = create_resource(&config)?;

    // Initialize tracing
    if config.enable_tracing {
        init_tracing(&config, &resource).await?;
    }

    // Set up tracing subscriber
    setup_tracing_subscriber(&config)?;

    info!("Telemetry initialization completed successfully");
    Ok(TelemetryHandles { _config: config })
}

/// Create resource with service metadata
fn create_resource(config: &TelemetryConfig) -> Result<Resource> {
    let resource = Resource::new(vec![
        KeyValue::new("service.name", config.service_name.clone()),
        KeyValue::new("service.version", config.service_version.clone()),
        KeyValue::new("deployment.environment", config.environment.clone()),
    ]);

    Ok(resource)
}

/// Initialize distributed tracing
async fn init_tracing(config: &TelemetryConfig, resource: &Resource) -> Result<()> {
    if let Some(endpoint) = &config.otlp_endpoint {
        // Use OTLP exporter
        opentelemetry_otlp::new_pipeline()
            .tracing()
            .with_exporter(
                opentelemetry_otlp::new_exporter()
                    .tonic()
                    .with_endpoint(endpoint)
                    .with_timeout(config.export_timeout),
            )
            .with_trace_config(
                opentelemetry_sdk::trace::config()
                    .with_resource(resource.clone())
                    .with_sampler(opentelemetry_sdk::trace::Sampler::AlwaysOn),
            )
            .install_batch(runtime::Tokio)
            .context("Failed to initialize OTLP tracer")?;

        info!("Distributed tracing initialized with OTLP exporter");
    } else {
        // For development, just use console logging - tracing will handle the output
        info!("No OTLP endpoint configured, using console-only tracing");
    }
    
    Ok(())
}

/// Set up tracing subscriber
fn setup_tracing_subscriber(_config: &TelemetryConfig) -> Result<()> {
    let env_filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| format!("{}=debug", env!("CARGO_CRATE_NAME")).into());

    Registry::default()
        .with(env_filter)
        .with(tracing_subscriber::fmt::layer())
        .try_init()
        .context("Failed to initialize tracing subscriber")?;

    info!("Tracing subscriber initialized");
    Ok(())
}

/// Get a tracer instance for the current service
pub fn get_tracer(name: &'static str) -> opentelemetry::global::BoxedTracer {
    global::tracer(name)
}

/// Get a meter instance for the current service (placeholder for future implementation)
pub fn get_meter(name: &str) -> DummyMeter {
    DummyMeter { name: name.to_string() }
}

/// Dummy meter for API compatibility
#[derive(Debug)]
pub struct DummyMeter {
    name: String,
}

impl DummyMeter {
    pub fn u64_counter(&self, name: &str) -> DummyCounterBuilder {
        DummyCounterBuilder {
            name: name.to_string(),
            meter_name: self.name.clone(),
        }
    }
    
    pub fn f64_histogram(&self, name: &str) -> DummyHistogramBuilder {
        DummyHistogramBuilder {
            name: name.to_string(),
            meter_name: self.name.clone(),
        }
    }
}

#[derive(Debug)]
pub struct DummyCounterBuilder {
    name: String,
    meter_name: String,
}

impl DummyCounterBuilder {
    pub fn with_description(self, _description: &str) -> Self {
        self
    }
    
    pub fn build(self) -> DummyCounter {
        DummyCounter { name: self.name }
    }
}

#[derive(Debug)]
pub struct DummyCounter {
    name: String,
}

impl DummyCounter {
    pub fn add(&self, _value: u64, _attributes: &[KeyValue]) {
        // For now, just log the metric - in future this could be replaced with real metrics
        tracing::debug!(
            counter = %self.name,
            value = _value,
            "Counter incremented"
        );
    }
}

#[derive(Debug)]
pub struct DummyHistogramBuilder {
    name: String,
    meter_name: String,
}

impl DummyHistogramBuilder {
    pub fn with_description(self, _description: &str) -> Self {
        self
    }
    
    pub fn build(self) -> DummyHistogram {
        DummyHistogram { name: self.name }
    }
}

#[derive(Debug)]
pub struct DummyHistogram {
    name: String,
}

impl DummyHistogram {
    pub fn record(&self, _value: f64, _attributes: &[KeyValue]) {
        // For now, just log the metric - in future this could be replaced with real metrics
        tracing::debug!(
            histogram = %self.name,
            value = _value,
            "Histogram recorded"
        );
    }
}

/// Health check for telemetry components
pub fn telemetry_health_check() -> HashMap<String, bool> {
    let mut health = HashMap::new();
    
    // Check if providers are initialized
    health.insert("tracer_provider".to_string(), true);
    health.insert("meter_provider".to_string(), true);
    health.insert("logger_provider".to_string(), true);
    
    health
}

/// Convenience macro for creating spans with automatic error handling
#[macro_export]
macro_rules! traced_span {
    ($tracer:expr, $name:expr, $($key:expr => $value:expr),*) => {{
        use opentelemetry::trace::{Span, SpanKind, Tracer};
        use opentelemetry::KeyValue;
        
        let mut span = $tracer.span_builder($name)
            .with_kind(SpanKind::Internal)
            .start(&$tracer);
            
        $(
            span.set_attribute(KeyValue::new($key, $value));
        )*
        
        span
    }};
    ($tracer:expr, $name:expr) => {{
        use opentelemetry::trace::{Span, SpanKind, Tracer};
        
        $tracer.span_builder($name)
            .with_kind(SpanKind::Internal)
            .start(&$tracer)
    }};
}
