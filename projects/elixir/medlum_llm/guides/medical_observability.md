# Medical Observability Guide

This guide explains how to use MedlumLlm.Metrics for medical AI observability, specifically designed for MedlumLlm and Clinical Verification Layer (CVL) monitoring.

## Overview

MedlumLlm.Metrics provides specialized metrics support for medical AI applications through the `MedlumLlm.Metrics` namespace. This includes:

- **Telemetry Integration** - Automatic capture of medical AI events
- **CVL Metrics** - Track hallucination detection and agent performance
- **Evaluation Metrics** - Record accuracy, latency, and errors
- **Dashboard Queries** - Pre-built aggregations for common dashboards
- **Alert Rules** - Medical-specific alerting thresholds

## Quick Start

### 1. Attach Medical Telemetry

At application startup, attach MetricsEx to medical telemetry events:

```elixir
# In your Application.start/2
def start(_type, _args) do
  # Attach medical telemetry handlers
  MedlumLlm.Metrics.Telemetry.attach_all()

  # Define standard medical alerts
  MedlumLlm.Metrics.Alerts.define_standard_alerts()

  # ... rest of startup
end
```

### 2. Record Metrics

The medical modules provide domain-specific recording functions:

```elixir
# Record evaluation accuracy
MedlumLlm.Metrics.Evaluation.record_accuracy(0.75,
  model: "biomistral_7b",
  dataset: "medqa",
  benchmark: "zero_shot"
)

# Record CVL verification
MedlumLlm.Metrics.CVL.record_verification(:entailment, 150.5,
  verifier_type: :ensemble,
  confidence: 0.92
)
```

### 3. Query Dashboard Data

Use the query helpers for dashboard aggregations:

```elixir
# Get hallucination detection metrics
metrics = MedlumLlm.Metrics.Queries.hallucination_detection_metrics()
# => %{precision: 0.92, recall: 0.88, f1: 0.90, ...}

# Get accuracy by model
accuracy = MedlumLlm.Metrics.Queries.accuracy_by_model(window: :last_7d)
# => %{"biomistral_7b/medqa" => %{mean: 0.75, count: 100}, ...}
```

## Telemetry Event Hierarchy

The medical telemetry module defines standard events for MedlumLlm:

### Evaluation Events

| Event | Type | Description |
|-------|------|-------------|
| `[:medlum_llm, :eval, :run, :start]` | counter | Evaluation run initiated |
| `[:medlum_llm, :eval, :run, :stop]` | histogram | Evaluation run completed |
| `[:medlum_llm, :eval, :sample, :stop]` | histogram | Sample processed successfully |
| `[:medlum_llm, :eval, :sample, :exception]` | counter | Sample processing failed |

### CVL Events

| Event | Type | Description |
|-------|------|-------------|
| `[:medlum_llm, :cvl, :verify, :stop]` | histogram | CVL verification completed |
| `[:medlum_llm, :cvl, :agent, :verdict]` | histogram | Individual agent verdict |
| `[:medlum_llm, :cvl, :consensus, :complete]` | histogram | Multi-agent consensus reached |

### Inference Events

| Event | Type | Description |
|-------|------|-------------|
| `[:medlum_llm, :chat, :complete]` | histogram | Chat completion finished |
| `[:medlum_llm, :embed, :complete]` | histogram | Embedding generation finished |

## CVL Metrics

The Clinical Verification Layer uses five specialized agents:

| Agent | Domain | Validation |
|-------|--------|------------|
| `:medication` | Drug information | RxNorm |
| `:lab` | Lab values | LOINC |
| `:ontology` | Clinical terms | SNOMED-CT/ICD-10 |
| `:temporal` | Timeline | Progression logic |
| `:differential` | Diagnosis | Symptom mapping |

### Recording Agent Verdicts

```elixir
alias MedlumLlm.Metrics.CVL

# Record overall verification result
CVL.record_verification(:contradiction, 150.5,
  verifier_type: :ensemble,
  confidence: 0.92,
  run_id: "run_123"
)

# Record individual agent verdicts
CVL.record_agent_verdict(:medication, :entailment, 45.2, confidence: 0.88)
CVL.record_agent_verdict(:lab, :entailment, 52.1, confidence: 0.85)
CVL.record_agent_verdict(:ontology, :contradiction, 38.5, confidence: 0.91)
CVL.record_agent_verdict(:temporal, :neutral, 41.0, confidence: 0.72)
CVL.record_agent_verdict(:differential, :entailment, 55.0, confidence: 0.80)

# Record consensus result
CVL.record_consensus(:entailment, 4, 180.0, run_id: "run_123")
```

### Tracking Hallucination Detection

Track the confusion matrix for hallucination detection:

```elixir
# Ground truth: was_hallucination indicates actual hallucination
# CVL flagged: cvl_flagged indicates CVL detected potential hallucination

# True positive: CVL caught a real hallucination
CVL.record_hallucination_detection(true, true)

# False positive: CVL flagged but wasn't a hallucination
CVL.record_hallucination_detection(true, false)

# False negative: CVL missed a hallucination
CVL.record_hallucination_detection(false, true)

# True negative: CVL correctly passed valid content
CVL.record_hallucination_detection(false, false)
```

## Evaluation Metrics

### Recording Accuracy

```elixir
alias MedlumLlm.Metrics.Evaluation

# Basic accuracy recording
Evaluation.record_accuracy(0.75,
  model: "biomistral_7b",
  dataset: "medqa",
  benchmark: "zero_shot"
)

# With Wilson confidence interval (computed via CrucibleBench)
Evaluation.record_accuracy_with_ci(0.75, 0.68, 0.81,
  model: "biomistral_7b",
  dataset: "medqa"
)
```

### Recording Latency

```elixir
Evaluation.record_latency(1523.5,
  model: "biomistral_7b",
  benchmark: "zero_shot",
  provider: :ollama
)
```

### Recording Errors

Error types are automatically categorized:

```elixir
Evaluation.record_error(:timeout, model: "biomistral_7b")
Evaluation.record_error(:provider_error, model: "openbiollm_8b")
Evaluation.record_error(:parse_error, model: "meditron_7b")
```

Supported error types:
- `:timeout` - Inference timeout
- `:provider_error` - Ollama/HuggingFace error
- `:parse_error` - Response parsing failed
- `:validation_error` - Response validation failed
- `:network_error` - Connection failures
- `:oom_error` - Out of memory
- `:unknown` - Unclassified error

## Dashboard Queries

### CVL Performance Dashboard

```elixir
alias MedlumLlm.Metrics.Queries

# Verdict distribution
verdicts = Queries.verdict_distribution(window: :last_24h)

# Agent performance (duration stats)
agents = Queries.agent_performance(window: :last_24h)

# Hallucination detection precision/recall/F1
detection = Queries.hallucination_detection_metrics()
# => %{precision: 0.92, recall: 0.88, f1: 0.90, ...}

# Consensus agreement distribution
consensus = Queries.consensus_distribution()
```

### Model Comparison Dashboard

```elixir
# Accuracy by model/dataset
accuracy = Queries.accuracy_by_model(window: :last_7d)

# Latency percentiles by model
latency = Queries.latency_by_model(window: :last_24h)

# Error distribution
errors = Queries.errors_by_type()
```

### Accuracy with Confidence Intervals

```elixir
# Get accuracy with Wilson CI bounds
results = Queries.accuracy_with_ci(model: "biomistral_7b")
# => [%{model: "biomistral_7b", accuracy: 0.75, ci_lower: 0.68, ci_upper: 0.81}, ...]
```

## Alert Configuration

### Standard Medical Alerts

```elixir
# Define all standard alerts
MedlumLlm.Metrics.Alerts.define_standard_alerts()
```

This configures:

| Alert | Condition | Threshold | Severity |
|-------|-----------|-----------|----------|
| `:low_accuracy` | accuracy < 0.50 | 0.50 | critical |
| `:cvl_critical_failure` | recall < 0.70 | 0.70 | critical |
| `:cvl_low_recall` | recall < 0.80 | 0.80 | warning |
| `:high_latency` | p95 > 10s | 10000ms | warning |
| `:high_error_rate` | rate > 10% | 0.10 | warning |
| `:low_consensus` | rate < 60% | 0.60 | warning |

### Custom Alerts

```elixir
alias MedlumLlm.Metrics.Alerts

# Define a custom alert
Alerts.define_alert(:custom_accuracy_threshold,
  metric: :medlum_eval_accuracy,
  condition: :less_than,
  threshold: 0.60,
  severity: :warning,
  message: "Accuracy dropped below 60% threshold"
)
```

### Selective Alert Groups

```elixir
# Only CVL alerts
Alerts.define_cvl_alerts()

# Only evaluation alerts
Alerts.define_eval_alerts()

# Remove all medical alerts
Alerts.remove_all()
```

## Prometheus Export

Export medical metrics in Prometheus format:

```elixir
# In Phoenix controller
defmodule MyAppWeb.MetricsController do
  use MyAppWeb, :controller

  def prometheus(conn, _params) do
    metrics = MetricsEx.Storage.Prometheus.export()

    conn
    |> put_resp_content_type(MetricsEx.Storage.Prometheus.content_type())
    |> send_resp(200, metrics)
  end
end
```

Example output:

```
# HELP medlum_eval_accuracy Model accuracy
# TYPE medlum_eval_accuracy gauge
medlum_eval_accuracy{model="biomistral_7b",dataset="medqa"} 0.75

# HELP medlum_cvl_verdict_count CVL verdict counts
# TYPE medlum_cvl_verdict_count counter
medlum_cvl_verdict_count{verdict="entailment",verifier_type="ensemble"} 1500
medlum_cvl_verdict_count{verdict="contradiction",verifier_type="ensemble"} 450
```

## Best Practices

### 1. Attach Early

Attach telemetry handlers early in your application startup to capture all events.

### 2. Use Run IDs

Always include `run_id` when recording evaluation metrics for correlation:

```elixir
run_id = "run_#{System.system_time(:millisecond)}"

Evaluation.record_accuracy(0.75,
  model: "biomistral_7b",
  dataset: "medqa",
  run_id: run_id
)
```

### 3. Track CI Bounds

For research-grade reporting, always record Wilson confidence intervals:

```elixir
# Compute CI using CrucibleBench
{ci_lower, ci_upper} = CrucibleBench.wilson_score(correct, total, 0.95)

Evaluation.record_accuracy_with_ci(accuracy, ci_lower, ci_upper, opts)
```

### 4. Monitor CVL Effectiveness

Regularly check hallucination detection metrics:

```elixir
metrics = Queries.hallucination_detection_metrics()

if metrics.recall < 0.80 do
  Logger.warning("CVL recall dropped below 80%: #{metrics.recall}")
end
```

### 5. Set Appropriate Retention

For medical evaluation data, consider longer retention:

```elixir
# config/config.exs
config :metrics_ex,
  retention_hours: 168  # 7 days
```

## Integration with MedlumLlm

The medical metrics integrate with MedlumLlm's evaluation harness:

```elixir
defmodule MedlumLlm.MetricsIntegration do
  alias MedlumLlm.Metrics.{CVL, Evaluation}

  def record_sample_result(result) do
    Evaluation.record_latency(result.latency_ms,
      model: result.model,
      benchmark: result.benchmark
    )

    if result.cvl_verification do
      CVL.record_verification(
        result.cvl_verification.verdict,
        result.cvl_verification.duration_ms,
        verifier_type: :ensemble
      )
    end
  end
end
```

## Troubleshooting

### No Metrics Recorded

1. Ensure telemetry is attached: `MedlumLlm.Metrics.Telemetry.attached?()`
2. Check that telemetry events are being emitted
3. Verify MetricsEx application is started

### Empty Query Results

1. Check time window - default is `:last_24h`
2. Verify metrics were recorded recently
3. Use `MetricsEx.get_stats()` to check storage

### Alert Not Triggering

1. Verify alert was defined: `MedlumLlm.Metrics.Alerts.get_config(:alert_name)`
2. Check that the metric is being recorded
3. Manually call `MetricsEx.Alerting.check_rules()` to test
