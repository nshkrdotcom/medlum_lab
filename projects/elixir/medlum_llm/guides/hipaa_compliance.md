# HIPAA Compliance Guide

This guide covers MedlumLlm's guardrails features for HIPAA-compliant medical LLM applications.

## Overview

MedlumLlm provides clinical PII detection and de-identification capabilities that support HIPAA compliance requirements. The guardrails system detects Protected Health Information (PHI) in text and provides options for redaction, date shifting, and age binning per the HIPAA Safe Harbor method.

## Key Modules

- `MedlumLlm.Guardrails` - Configuration and validation pipeline
- `MedlumLlm.Detectors.ClinicalPII` - PHI detection implementing `LlmGuard.Detector`
- `MedlumLlm.Guardrails.Redactor` - De-identification and redaction
- `MedlumLlm.Guardrails.Audit` - HIPAA-compliant audit logging

## Detected PHI Types

### Tier 1: High Confidence (Fixed Format)

| Type | Examples | Confidence |
|------|----------|------------|
| MRN | `MRN: 12345678`, `Patient ID: A123456` | 85-95% |
| DOB | `DOB: 01/15/1980`, `Date of Birth: 1980-01-15` | 95% |
| NPI | `NPI: 1234567890` | 95% |
| DEA | `DEA: AB1234567` | 95% |

### Tier 2: Medium Confidence (Variable Format)

| Type | Examples | Confidence |
|------|----------|------------|
| Medical Date | `Admitted: 03/15/2024`, `DOA: 12/01/2024` | 85-90% |
| Insurance ID | `Policy: ABC123456789`, `Member ID: XYZ987` | 75-90% |
| Medicare ID | `HICN: 123456789A` | 90% |
| Room/Bed | `Room 204B`, `Bed 3` | 70-85% |

### Tier 3: Lower Confidence (Context-Dependent)

| Type | Examples | Confidence |
|------|----------|------------|
| Provider Name | `Dr. Smith`, `Jane Doe, MD` | 60-80% |
| Facility Name | `Memorial Hospital`, `Mayo Clinic` | 65-80% |

## Usage

### Basic Validation

```elixir
# Validate input before sending to LLM
case MedlumLlm.Guardrails.validate_input(user_text) do
  {:ok, text} ->
    # Safe to process
    response = MedlumLlm.Chat.generate(text)

  {:detected, result} ->
    # PHI detected in input
    Logger.warning("PHI detected: #{inspect(result.patterns_matched)}")
end
```

### Output Validation with Automatic Redaction

```elixir
# Validate and automatically redact LLM output
case MedlumLlm.Guardrails.validate_output(llm_response) do
  {:ok, safe_text} ->
    # No PHI detected, return as-is
    safe_text

  {:ok, redacted_text, manifest} ->
    # PHI was detected and redacted
    # manifest contains audit information
    Logger.info("Redacted #{manifest.redaction_count} items")
    redacted_text
end
```

### Full Pipeline

```elixir
# Validate input -> process -> validate output in one call
result = MedlumLlm.Guardrails.pipeline(
  user_input,
  fn safe_input -> MedlumLlm.Chat.generate(safe_input) end
)

case result do
  {:ok, safe_response} -> safe_response
  {:error, :phi_detected, details} -> handle_blocked(details)
end
```

## Configuration Profiles

### Standard Clinical Use

```elixir
# Default configuration for real-time clinical applications
config = MedlumLlm.Guardrails.config(
  confidence_threshold: 0.7,      # Balanced precision/recall
  include_tier_3: false,          # Exclude name patterns (higher FP rate)
  redaction_strategy: :placeholder
)
```

### CVL Training Data Export

```elixir
# Aggressive configuration for research data export
config = MedlumLlm.Guardrails.export_config(
  seed: "study_20260125"  # Deterministic for reproducibility
)
# Automatically enables:
# - Tier 3 patterns (names, facilities)
# - Lower confidence threshold (0.5)
# - Hash-based redaction
# - Safe Harbor strict mode
```

### Clinical-Only Detection

```elixir
# Skip prompt injection checks when input source is trusted
config = MedlumLlm.Guardrails.clinical_config(
  include_tier_3: true,
  confidence_threshold: 0.6
)
```

## HIPAA Safe Harbor De-identification

The Safe Harbor method specifies 18 identifiers that must be removed:

1. Names ✓
2. Geographic data smaller than state
3. Dates except year related to individual ✓
4. Phone numbers (via LlmGuard)
5. Fax numbers
6. Email addresses (via LlmGuard)
7. Social Security Numbers (via LlmGuard)
8. Medical record numbers ✓
9. Health plan beneficiary numbers ✓
10. Account numbers
11. Certificate/license numbers
12. Vehicle identifiers
13. Device identifiers
14. Web URLs (via LlmGuard)
15. IP addresses (via LlmGuard)
16. Biometric identifiers
17. Full-face photos
18. Any unique identifier

✓ = Directly supported by MedlumLlm clinical patterns

### Age Binning

Per HIPAA Safe Harbor, ages over 89 must be aggregated:

```elixir
# Single age
MedlumLlm.Guardrails.Redactor.bin_age(92)
# => "90+"

# Ages in text
text = "Patient is a 95-year-old male"
MedlumLlm.Guardrails.Redactor.bin_ages_in_text(text)
# => "Patient is a 90+-year-old male"
```

### Date Shifting

Preserve temporal relationships while removing absolute dates:

```elixir
text = "Admitted: 01/15/2025, Discharged: 01/20/2025"
MedlumLlm.Guardrails.Redactor.shift_dates(text, 30)
# => "Admitted: 02/14/2025, Discharged: 02/19/2025"
# Interval of 5 days is preserved
```

## Audit Logging

All operations can be logged without exposing PHI:

```elixir
# Redaction with audit
{redacted, manifest} = MedlumLlm.Guardrails.Redactor.redact_with_manifest(text)

# Log the operation
{:ok, entry} = MedlumLlm.Guardrails.Audit.log_redaction(
  manifest,
  "user_123",      # operator ID
  "session_abc"    # session ID
)

# Entry contains:
# - timestamp
# - input_hash (SHA256, not content)
# - output_hash
# - redaction_types (list of atom types)
# - redaction_count
# - operator_id, session_id
```

### Telemetry Events

Subscribe to guardrail events for monitoring:

```elixir
:telemetry.attach(
  "guardrails-monitor",
  [:medlum_llm, :guardrails, :redaction],
  fn event, measurements, metadata, _config ->
    # measurements.count = number of redactions
    # metadata.redaction_types = list of PHI types
    # metadata.operator_id, metadata.session_id
  end,
  nil
)
```

Available events:
- `[:medlum_llm, :guardrails, :redaction]`
- `[:medlum_llm, :guardrails, :validation]`
- `[:medlum_llm, :guardrails, :error]`

## LlmGuard Integration

MedlumLlm's clinical detector implements `LlmGuard.Detector` for pipeline integration:

```elixir
# Use with LlmGuard pipeline
config = LlmGuard.Config.new(
  prompt_injection_detection: true,
  jailbreak_detection: true,
  data_leakage_prevention: true,
  enabled_detectors: [MedlumLlm.Detectors.ClinicalPII],
  custom_options: %{
    clinical_pii: %{
      include_tier_3: false,
      confidence_threshold: 0.7
    }
  }
)

case LlmGuard.validate_input(user_input, config) do
  {:ok, safe_input} -> process(safe_input)
  {:error, :detected, details} -> block(details)
end
```

## Context Boosting

Detection confidence increases when medical context keywords appear nearby:

| Pattern Type | Context Keywords |
|--------------|------------------|
| MRN | patient, chart, record, admit |
| DOB | patient, born, age, birthday |
| NPI | provider, physician, doctor, prescriber |
| DEA | prescriber, controlled, narcotic |
| Insurance | insurance, coverage, plan, payer |
| Room/Bed | admitted, patient, ward, floor |

Example:
```elixir
# Lower confidence (no context)
"12345678"  # May not trigger MRN detection

# Higher confidence (with context)
"Patient chart MRN: 12345678"  # Clear MRN detection
```

## Best Practices

1. **Use appropriate mode**: `automatic` for real-time, `aggressive` for exports
2. **Log all operations**: Use `Audit.log_redaction/3` for compliance
3. **Set deterministic seeds**: For reproducible research, use same seed
4. **Test with realistic data**: Clinical patterns vary by institution
5. **Review Tier 3 patterns**: Name detection has higher false positive rate
6. **Combine with LlmGuard**: Use full pipeline for prompt injection + PHI detection

## Limitations

1. **Not a complete HIPAA solution**: Covers detection/redaction, not access control, encryption, etc.
2. **Pattern-based**: May miss novel identifier formats
3. **No learning**: Patterns don't improve from false positives
4. **Name detection**: Context-dependent, higher false positive rate
5. **Requires tuning**: Institution-specific patterns may need adjustment
