# MedOntology

[![Hex.pm](https://img.shields.io/hexpm/v/med_ontology_ex.svg)](https://hex.pm/packages/med_ontology_ex)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/med_ontology_ex)

Unified medical ontology lookup service for Elixir.

Provides access to SNOMED-CT, ICD-10-CM, RxNorm, and LOINC ontologies through a consistent API. Designed for clinical NLP applications and the MedlumLlm Clinical Verification Layer (CVL).

## Features

- **Unified API** - Single interface for all four ontologies
- **Offline Operation** - ETS/DETS caching for air-gapped clinical environments
- **High Performance** - Sub-10ms cached lookups with ETS
- **OTP-Native** - Built on GenServer, Supervision trees, and Telemetry
- **Cross-Ontology Mapping** - SNOMED-CT to ICD-10, RxNorm to NDC
- **CVL Integration** - Built for LLM hallucination detection in clinical summaries

## Installation

Add `med_ontology_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:med_ontology_ex, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Look up concepts
{:ok, concept} = MedOntology.lookup(:snomed_ct, "44054006")
# => %Concept{code: "44054006", display: "Type 2 diabetes mellitus"}

{:ok, concept} = MedOntology.lookup(:rxnorm, "861004")
# => %Concept{code: "861004", display: "metformin 500 MG Oral Tablet"}

# Search by text
{:ok, results} = MedOntology.search(:snomed_ct, "hypertension")

# Validate codes
MedOntology.valid?(:icd10, "E11.9")
# => true

# Cross-ontology mapping
{:ok, mappings} = MedOntology.map(:snomed_ct, "44054006", :icd10)
```

## Ontology-Specific Features

### RxNorm

```elixir
# Normalize drug strings to RxNorm concepts
{:ok, concept} = MedOntology.RxNorm.normalize("metformin 500mg tablet")

# Get drug class (ATC, VA, NDF-RT)
{:ok, classes} = MedOntology.RxNorm.drug_class("861004")
# => %{atc: ["A10BA02"], va_class: ["HS502"], ndf_rt: [...]}

# Get ingredients
{:ok, ingredients} = MedOntology.RxNorm.ingredients("861004")
# => [%Concept{code: "6809", display: "Metformin"}]

# Get NDC codes
{:ok, ndcs} = MedOntology.RxNorm.ndc_codes("861004")

# Check drug interactions
{:ok, interactions} = MedOntology.RxNorm.interactions("861004", "197361")
```

### LOINC

```elixir
# Get LOINC parts (6-part axis)
{:ok, parts} = MedOntology.LOINC.parts("4548-4")
# => %{component: "Hemoglobin A1c", property: "MFr", system: "Bld", ...}

# Get reference range
{:ok, range} = MedOntology.LOINC.reference_range("4548-4")
# => %{low: 4.0, high: 5.6, unit: "%"}

# Evaluate lab value against reference range
{:ok, :high} = MedOntology.LOINC.evaluate_value("4548-4", 7.2)
# Returns :normal, :low, :high, :critical_low, or :critical_high

# Get panel members
{:ok, members} = MedOntology.LOINC.panel_members("24323-8")
# => [%Concept{code: "2345-7", display: "Glucose"}, ...]

# Check if code is a panel
MedOntology.LOINC.panel?("24323-8")
# => true
```

### ICD-10

```elixir
# Check billability
MedOntology.ICD10.billable?("E11.9")
# => true

MedOntology.ICD10.billable?("E11")
# => false (category code, not specific enough)

# Validate format
MedOntology.ICD10.valid_format?("E11.9")
# => true

# Get hierarchy
{:ok, hierarchy} = MedOntology.ICD10.hierarchy("E11.9")
# => %{
#   chapter: "IV",
#   chapter_title: "Endocrine, nutritional and metabolic diseases",
#   block: "E10-E14",
#   block_title: "Diabetes mellitus",
#   category: "E11",
#   code: "E11.9",
#   billable: true
# }

# Get exclusion codes
{:ok, exclusions} = MedOntology.ICD10.exclusions("E11")
```

### SNOMED-CT

```elixir
# Check is-a relationships (transitive)
MedOntology.SnomedCT.is_a?("44054006", "73211009")
# => true (Type 2 DM is-a Diabetes mellitus)

# Get relationships
{:ok, rels} = MedOntology.SnomedCT.relationships("44054006")

# ECL queries (Expression Constraint Language)
{:ok, concepts} = MedOntology.SnomedCT.ecl_query("<< 73211009")
# => All descendants of Diabetes mellitus

# Get semantic tag
{:ok, tag} = MedOntology.SnomedCT.semantic_tag("44054006")
# => "disorder"

# Get ancestors
{:ok, ancestors} = MedOntology.ancestors(:snomed_ct, "44054006")
```

## Batch Operations

```elixir
# Batch lookup
{:ok, results} = MedOntology.lookup_batch(:icd10, ["E11.9", "I10", "J06.9"])
# => %{"E11.9" => %Concept{...}, "I10" => %Concept{...}, "J06.9" => %Concept{...}}

# Parallel processing with Task.async_stream
medications
|> Task.async_stream(fn med ->
  MedOntology.RxNorm.normalize(med)
end, max_concurrency: 10)
|> Enum.to_list()
```

## Cache Management

```elixir
# Warm up cache from disk
MedOntology.warmup([:snomed_ct, :rxnorm])

# Get cache statistics
MedOntology.cache_stats()
# => %{
#   snomed_ct: %{size: 50000, memory_bytes: 100000000},
#   rxnorm: %{size: 10000, memory_bytes: 20000000},
#   ...
# }

# Clear cache
MedOntology.clear_cache([:rxnorm])
```

## Configuration

```elixir
config :med_ontology_ex,
  # Cache directory for DETS persistence
  cache_dir: "/var/lib/med_ontology/cache",

  # Warmup cache on application start
  cache_warmup_on_start: true,

  # API credentials (optional - for online operation)
  umls_api_key: System.get_env("UMLS_API_KEY"),
  loinc_username: System.get_env("LOINC_USERNAME"),
  loinc_password: System.get_env("LOINC_PASSWORD"),

  # Background sync (disabled by default for air-gapped environments)
  sync_enabled: false,
  sync_interval_hours: 24,

  # HTTP timeout
  http_timeout_ms: 5_000
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│              MedOntology (Public API)           │
└─────────────────────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│  SnomedCT   │ │   RxNorm    │ │    ICD10    │ ...
└─────────────┘ └─────────────┘ └─────────────┘
        │               │               │
        └───────────────┼───────────────┘
                        ▼
┌─────────────────────────────────────────────────┐
│          Cache Layer (ETS + DETS)               │
└─────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────┐
│          Client Layer (HTTP via Finch)          │
└─────────────────────────────────────────────────┘
```

## CVL Integration

The library is designed for integration with the MedlumLlm Clinical Verification Layer:

```elixir
defmodule MyCVL.MedicationAgent do
  def verify_medication(claim_text) do
    case MedOntology.RxNorm.normalize(claim_text) do
      {:ok, concept} ->
        {:ok, classes} = MedOntology.RxNorm.drug_class(concept.code)
        {:entailment, %{rxcui: concept.code, atc: classes.atc}}

      {:error, :not_found} ->
        {:contradiction, "Unknown medication: #{claim_text}"}
    end
  end
end

defmodule MyCVL.LabAgent do
  def verify_lab_value(loinc_code, value) do
    case MedOntology.LOINC.evaluate_value(loinc_code, value) do
      {:ok, :normal} -> {:entailment, "Value within normal range"}
      {:ok, :critical_high} -> {:neutral, "Critically elevated - verify"}
      {:ok, :critical_low} -> {:neutral, "Critically low - verify"}
      {:ok, status} -> {:entailment, "Value is #{status}"}
      {:error, _} -> {:neutral, "No reference range available"}
    end
  end
end
```

## Telemetry

The library emits telemetry events for observability:

- `[:med_ontology, :lookup, :start | :stop]`
- `[:med_ontology, :search, :start | :stop]`
- `[:med_ontology, :cache, :hit | :miss]`
- `[:med_ontology, :api, :request]`
- `[:med_ontology, :snomed_ct | :rxnorm | :icd10 | :loinc, :lookup, :stop]`

## Examples

The `examples/` directory contains runnable example scripts:

```bash
# Basic usage examples
mix run examples/basic_usage.exs

# CVL integration patterns
mix run examples/cvl_integration.exs

# Batch processing patterns
mix run examples/batch_processing.exs
```

## Requirements

- Elixir 1.15+
- Erlang/OTP 25+

## API Credentials

To access the underlying terminology services online, you may need:

- **UMLS API Key** - [Register at NLM](https://uts.nlm.nih.gov/uts/signup-login)
- **LOINC Account** - [Register at LOINC.org](https://loinc.org/register/)
- **WHO ICD API** - [Request access](https://icd.who.int/icdapi)

Note: The library supports fully offline operation with pre-populated caches.

## Supported Ontologies

| Ontology | Description | Primary Source | License |
|----------|-------------|----------------|---------|
| SNOMED-CT | Clinical terminology | Snowstorm API | Free in US (NLM) |
| ICD-10-CM | Diagnosis codes | CMS/WHO | Free (CMS/WHO) |
| RxNorm | Medication terminology | RxNav API | Free (NLM) |
| LOINC | Lab/observation codes | LOINC FHIR | Free (Regenstrief) |

## License

Apache License 2.0

Note: The underlying medical ontologies have their own licenses:
- SNOMED-CT: SNOMED International license (free in US via NLM)
- RxNorm: Public domain (NLM)
- LOINC: Regenstrief license (free registration required)
- ICD-10-CM: Public domain (CMS)

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Related Projects

- [MedlumLlm](../medlum_llm/README.md) - Clinical NLP and LLM verification
