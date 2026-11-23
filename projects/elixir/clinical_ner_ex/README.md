# ClinicalNerEx

[![Hex.pm](https://img.shields.io/hexpm/v/clinical_ner_ex.svg)](https://hex.pm/packages/clinical_ner_ex)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/clinical_ner_ex)

Clinical Named Entity Recognition (NER) for medical text in Elixir.

Extracts structured medical entities from unstructured clinical text including medications, lab values, diagnoses, procedures, and temporal expressions.

## Features

- **Multiple Entity Types**: Extract medications, lab values, diagnoses, procedures, and temporal expressions
- **Flexible Extraction Methods**: Rule-based (fast), transformer-based (accurate), or hybrid approach
- **Ontology Linking**: Link entities to RxNorm, LOINC, SNOMED-CT, and ICD-10 codes
- **OTP-Native**: Built for Elixir with supervision trees, telemetry, and parallel processing
- **Configurable**: Per-entity-type methods and confidence thresholds
- **CVL Integration**: Designed for Clinical Verification Layer agents

## Installation

Add `clinical_ner_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:clinical_ner_ex, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Extract all entity types
{:ok, entities} = ClinicalNerEx.extract("Patient on metformin 500mg BID for type 2 diabetes")

# Extract specific entity types
{:ok, meds} = ClinicalNerEx.extract_medications("lisinopril 10mg PO daily")
{:ok, labs} = ClinicalNerEx.extract_lab_values("A1c 6.5%, Cr 1.1 mg/dL")
{:ok, dx} = ClinicalNerEx.extract_diagnoses("h/o HTN, DM")
{:ok, procs} = ClinicalNerEx.extract_procedures("s/p CABG x3")
{:ok, temps} = ClinicalNerEx.extract_temporal("Started on 1/15/2026")

# With options
{:ok, entities} = ClinicalNerEx.extract(text,
  method: :hybrid,
  confidence_threshold: 0.8,
  link_ontologies: true
)
```

## Entity Types

| Type | Description | Ontology |
|------|-------------|----------|
| `:medication` | Drug names, doses, frequencies, routes | RxNorm |
| `:lab_value` | Lab tests, values, units, reference ranges | LOINC |
| `:diagnosis` | Conditions, symptoms, findings | SNOMED-CT, ICD-10 |
| `:procedure` | Medical procedures, surgeries | SNOMED-CT |
| `:temporal` | Dates, times, durations | - |

## Extraction Methods

- **`:rule_based`** - Fast regex/pattern matching (< 10ms)
- **`:transformer`** - ML model inference via Bumblebee (< 100ms)
- **`:hybrid`** - Combined approach (default)

## Configuration

```elixir
config :clinical_ner_ex,
  default_method: :hybrid,
  confidence_thresholds: %{
    medication: 0.8,
    lab_value: 0.75,
    diagnosis: 0.7,
    procedure: 0.7,
    temporal: 0.9
  },
  extraction_timeout_ms: 500,
  enable_ontology_linking: true
```

## Entity Structure

```elixir
%ClinicalNerEx.Entity{
  id: "abc123",
  type: :medication,
  text: "metformin 500mg BID",
  start_offset: 12,
  end_offset: 31,
  confidence: 0.95,
  attributes: %{
    drug_name: "metformin",
    dose: 500,
    dose_unit: "mg",
    frequency: "BID"
  },
  ontology_links: [
    %{system: :rxnorm, code: "861004", display: "metformin 500mg tablet", confidence: 0.92}
  ],
  extraction_method: :hybrid,
  warnings: [],
  metadata: %{}
}
```

## Batch Processing

```elixir
# Process multiple texts in parallel
texts = [
  "Patient on lisinopril 10mg daily",
  "Labs: A1c 7.2%, Cr 1.1",
  "History of COPD, hypertension"
]

{:ok, results} = ClinicalNerEx.extract_batch(texts)

# Stream processing for large document sets
File.stream!("clinical_notes.txt")
|> Stream.map(&String.trim/1)
|> ClinicalNerEx.extract_stream()
|> Enum.each(fn entities ->
  # Process entities
end)
```

## Pipeline Architecture

The library uses a pipeline-based architecture:

```
Text Input -> Preprocessor -> Coordinator -> Postprocessor -> Linker -> Output
```

### Pipeline Stages

1. **Preprocessor**: Text normalization, sentence segmentation
2. **Coordinator**: Parallel entity extraction across extractors
3. **Postprocessor**: Entity merging, deduplication, confidence filtering
4. **Linker**: Ontology code assignment via med_ontology_ex

### Key Components

- **Extractors**: Entity-specific extraction modules (`Medication`, `LabValue`, `Diagnosis`, `Procedure`, `Temporal`)
- **Methods**: Extraction strategies (RuleBased, Transformer, Hybrid)
- **Linkers**: Ontology linking modules (`RxNorm`, `LOINC`, `SNOMED`, `ICD10`)

## CVL Integration

This library is designed to integrate with Clinical Verification Layer (CVL) agents for hallucination detection:

```elixir
# Extract entities from claim and source
{:ok, claim_meds} = ClinicalNerEx.extract_medications(claim_text)
{:ok, source_meds} = ClinicalNerEx.extract_medications(source_text)

# Compare for verification
claim_drugs = Enum.map(claim_meds, & &1.attributes[:drug_name])
source_drugs = Enum.map(source_meds, & &1.attributes[:drug_name])
verified = Enum.filter(claim_drugs, fn d -> d in source_drugs end)
```

See `examples/cvl_integration.exs` for complete integration examples.

## Telemetry Events

The library emits telemetry events for monitoring:

- `[:clinical_ner_ex, :extract, :start]` - Extraction started
- `[:clinical_ner_ex, :extract, :stop]` - Extraction completed
- `[:clinical_ner_ex, :extract, :exception]` - Extraction failed
- `[:clinical_ner_ex, :linker, :cache_hit]` - Linker cache hit
- `[:clinical_ner_ex, :linker, :cache_miss]` - Linker cache miss

Example handler:

```elixir
:telemetry.attach(
  "my-handler",
  [:clinical_ner_ex, :extract, :stop],
  fn _event, measurements, metadata, _config ->
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    Logger.info("Extracted #{metadata.entity_count} entities in #{duration_ms}ms")
  end,
  nil
)
```

## Examples

Run the included examples:

```bash
# Basic extraction examples
mix run examples/basic_extraction.exs

# CVL integration examples
mix run examples/cvl_integration.exs
```

## Dependencies

- `med_ontology_ex` - For ontology lookups (RxNorm, LOINC, SNOMED-CT, ICD-10)
- `bumblebee` - For transformer-based extraction (optional)
- `telemetry` - For observability

## Testing

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Quality checks
mix quality
```

## Performance

- Rule-based extraction: < 10ms per document
- Hybrid extraction: < 50ms per document
- Batch processing: Up to 4 concurrent extractions by default

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please read the contributing guidelines for details.

## Acknowledgments

This library is part of the MedlumLlm project for clinical NLP and hallucination detection.
