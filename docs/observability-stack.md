# Observability Stack

This document describes the complete observability stack for the OHS Backend application, including distributed tracing with Jaeger, metrics collection, and log aggregation.

## 📊 **Stack Components**

### **Jaeger** - Distributed Tracing
- **Purpose**: Collect, store, and visualize distributed traces
- **UI**: http://localhost:16686
- **OTLP Endpoint**: http://localhost:4317 (gRPC)

### **OpenTelemetry Collector** (Optional)
- **Purpose**: Collect, process, and export telemetry data
- **Health Check**: http://localhost:13133
- **Metrics**: http://localhost:8888/metrics
- **Z-Pages**: http://localhost:55679

### **OHS Backend** - Application
- **Purpose**: Generate telemetry data (traces, metrics, logs)
- **Health Check**: http://localhost:8000/health (includes telemetry status)

## 🚀 **Quick Start**

### **1. Start Basic Stack (Jaeger + Backend)**

```bash
# Start services with Jaeger for tracing
docker-compose up -d postgres redis jaeger ohs-backend
```

**Access Points:**
- **Jaeger UI**: http://localhost:16686
- **Application**: http://localhost:8000
- **Health Check**: http://localhost:8000/health

### **2. Start Full Observability Stack**

```bash
# Start all services including OpenTelemetry Collector
docker-compose --profile observability up -d
```

**Additional Access Points:**
- **OTEL Collector Health**: http://localhost:13133
- **OTEL Collector Metrics**: http://localhost:8888/metrics
- **OTEL Collector Z-Pages**: http://localhost:55679

## 🔧 **Configuration**

### **Environment Variables**

The docker-compose setup automatically configures:

```yaml
# In docker-compose.yml - ohs-backend service
OTEL_EXPORTER_OTLP_ENDPOINT: http://jaeger:4317
OTEL_SERVICE_NAME: ohs-backend
OTEL_SERVICE_VERSION: 0.1.0
DEPLOYMENT_ENVIRONMENT: development
OTEL_TRACES_ENABLED: true
OTEL_METRICS_ENABLED: true
OTEL_LOGS_ENABLED: true
```

### **Local Development**

For local development (without Docker), update `.env`:

```env
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
```

## 📈 **Using the Observability Stack**

### **1. Generate Traces**

Start the application and make some requests:

```bash
# Health check (generates traces)
curl http://localhost:8000/health

# Make API requests to generate more traces
curl http://localhost:8000/
curl http://localhost:8000/admin
```

### **2. View Traces in Jaeger**

1. Open Jaeger UI: http://localhost:16686
2. Select **Service**: `ohs-backend`
3. Click **Find Traces**
4. Click on any trace to see details

### **3. Monitor Metrics**

**Application Metrics** (via health endpoint):
```bash
curl http://localhost:8000/health | jq '.services.telemetry'
```

**OTEL Collector Metrics** (if using full stack):
```bash
curl http://localhost:8888/metrics
```

### **4. View Logs**

Application logs with trace correlation:
```bash
docker-compose logs -f ohs-backend
```

## 🔍 **Trace Examples**

### **HTTP Request Trace**

Every HTTP request generates a trace with:
- **Span Name**: `GET /health`, `POST /api/users`, etc.
- **Attributes**:
  - `http.method`: HTTP method
  - `http.url`: Full URL
  - `http.route`: Route pattern
  - `http.status_code`: Response status
  - `http.response_time_ms`: Response time

### **Custom Business Logic Traces**

Add custom spans in your code:

```rust
use crate::telemetry::get_tracer;
use opentelemetry::{trace::Tracer, KeyValue};

let tracer = get_tracer("business-logic");
let mut span = tracer
    .span_builder("user_registration")
    .start(&tracer);

span.set_attribute(KeyValue::new("user.id", "12345"));
span.set_attribute(KeyValue::new("user.email", "user@example.com"));

// Your business logic here...

span.end();
```

## 🧪 **Testing the Setup**

### **1. Run Telemetry Demo**

```bash
# Run the telemetry demonstration
cargo run --example telemetry_demo

# Then check Jaeger UI for the generated traces
```

### **2. Load Testing**

Generate multiple traces for testing:

```bash
# Simple load test
for i in {1..10}; do
  curl -s http://localhost:8000/health > /dev/null
  echo "Request $i sent"
  sleep 1
done
```

### **3. Verify Data Flow**

1. **Application → Jaeger (Direct)**:
   - Check Jaeger UI for traces
   - Verify service appears in service list

2. **Application → OTEL Collector → Jaeger** (if using full stack):
   - Check OTEL Collector logs: `docker-compose logs otel-collector`
   - Verify traces still appear in Jaeger UI

## 🔧 **Advanced Configuration**

### **Production Setup**

For production, modify the configuration:

```yaml
# In docker-compose.yml or .env
OTEL_TRACES_SAMPLER_ARG: 0.1  # 10% sampling
DEPLOYMENT_ENVIRONMENT: production
OTEL_EXPORTER_OTLP_ENDPOINT: http://your-jaeger-instance:4317
```

### **Custom OTEL Collector Config**

Modify `otel-collector-config.yaml` to:
- Add more exporters (Prometheus, Elasticsearch, etc.)
- Configure different processors
- Set up custom pipelines

### **Jaeger Persistence**

Add persistent storage to Jaeger:

```yaml
jaeger:
  image: jaegertracing/all-in-one:1.58
  environment:
    - SPAN_STORAGE_TYPE=badger
    - BADGER_EPHEMERAL=false
    - BADGER_DIRECTORY_VALUE=/badger/data
    - BADGER_DIRECTORY_KEY=/badger/key
  volumes:
    - jaeger-data:/badger
```

## 🚨 **Troubleshooting**

### **No Traces Appearing**

1. **Check Application Logs**:
   ```bash
   docker-compose logs ohs-backend | grep -i telemetry
   ```

2. **Verify Jaeger Connection**:
   ```bash
   # Test OTLP endpoint
   curl -v http://localhost:4317
   ```

3. **Check Environment Variables**:
   ```bash
   docker-compose exec ohs-backend env | grep OTEL
   ```

### **OTEL Collector Issues**

1. **Check Collector Health**:
   ```bash
   curl http://localhost:13133
   ```

2. **View Collector Logs**:
   ```bash
   docker-compose logs otel-collector
   ```

### **Performance Issues**

1. **Reduce Sampling Rate**:
   ```env
   OTEL_TRACES_SAMPLER_ARG=0.01  # 1% sampling
   ```

2. **Increase Batch Sizes**:
   ```yaml
   # In otel-collector-config.yaml
   processors:
     batch:
       send_batch_size: 2048
       timeout: 5s
   ```

## 📚 **Additional Resources**

- **Jaeger Documentation**: https://www.jaegertracing.io/docs/
- **OpenTelemetry Rust**: https://docs.rs/opentelemetry/
- **OTEL Collector**: https://opentelemetry.io/docs/collector/
- **Tracing Best Practices**: https://opentelemetry.io/docs/specs/otel/trace/api/#general-requirements

## 🎯 **Next Steps**

1. **Add Prometheus** for metrics visualization
2. **Add Grafana** for dashboards
3. **Configure alerting** based on traces/metrics
4. **Add log aggregation** with ELK stack or Loki
5. **Implement SLOs/SLIs** based on trace data 