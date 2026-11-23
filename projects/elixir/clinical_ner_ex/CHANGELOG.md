# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-01-25

### Added

- Initial release of clinical_ner_ex
- Core data structures
  - `ClinicalNerEx.Entity` struct for extracted entities
  - Type-specific attribute structs (`Medication`, `LabValue`, `Diagnosis`, `Procedure`, `Temporal`)
- Extractor behaviour (`ClinicalNerEx.Extractors.Behaviour`)
- OTP Application with supervision tree
  - `ClinicalNerEx.Cache` for ETS-based caching
  - `Task.Supervisor` for parallel extraction
  - `DynamicSupervisor` for ML model serving
- Public API
  - `ClinicalNerEx.extract/2` - Generic extraction
  - `ClinicalNerEx.extract_medications/2` - Medication extraction
  - `ClinicalNerEx.extract_lab_values/2` - Lab value extraction
  - `ClinicalNerEx.extract_diagnoses/2` - Diagnosis extraction
  - `ClinicalNerEx.extract_procedures/2` - Procedure extraction
  - `ClinicalNerEx.extract_temporal/2` - Temporal expression extraction
  - `ClinicalNerEx.extract_batch/2` - Batch extraction
  - `ClinicalNerEx.extract_stream/2` - Stream extraction
  - `ClinicalNerEx.config/0` - Configuration access

### Pipeline Implementation

- Complete pipeline architecture with four stages:
  - `ClinicalNerEx.Pipeline.Preprocessor` - Text normalization and sentence segmentation
  - `ClinicalNerEx.Pipeline.Coordinator` - Parallel entity extraction coordination
  - `ClinicalNerEx.Pipeline.Postprocessor` - Entity merging, deduplication, confidence filtering
  - `ClinicalNerEx.Linker` - Ontology code assignment

### Extractors

- `ClinicalNerEx.Extractors.Medication` - Rule-based medication extraction
  - Drug name, dose, dose_unit, frequency, route, duration, PRN detection
  - Confidence scoring based on extraction completeness
- `ClinicalNerEx.Extractors.LabValue` - Rule-based lab value extraction
  - Lab name normalization, value/unit extraction, reference ranges, abnormal flags
  - Support for percentage values and electrolyte shorthand
- `ClinicalNerEx.Extractors.Diagnosis` - Rule-based diagnosis extraction
  - Abbreviation expansion (HTN, DM, COPD, etc.)
  - Status detection (active, historical, suspected, ruled_out)
  - Severity and laterality extraction
- `ClinicalNerEx.Extractors.Procedure` - Rule-based procedure extraction
  - Common procedure abbreviations (CABG, CT, MRI, EKG, etc.)
  - Surgery pattern matching
  - Status detection (completed, planned, pending)
- `ClinicalNerEx.Extractors.Temporal` - Rule-based temporal extraction
  - US and ISO date formats
  - Durations (days, weeks, months, years)
  - Relative expressions (yesterday, next week, etc.)
  - Time patterns (12h and 24h formats)

### Ontology Linking

- `ClinicalNerEx.Linker.RxNorm` - Medication to RxNorm linking
- `ClinicalNerEx.Linker.LOINC` - Lab values to LOINC linking
- `ClinicalNerEx.Linker.SNOMED` - Diagnosis/Procedure to SNOMED-CT linking
- `ClinicalNerEx.Linker.ICD10` - Diagnosis to ICD-10 linking

### Configuration

- `ClinicalNerEx.Config` module with configurable options:
  - `default_method` - Extraction method (:rule_based, :transformer, :hybrid)
  - `confidence_thresholds` - Per-entity-type confidence thresholds
  - `extraction_timeout_ms` - Extraction timeout
  - `enable_ontology_linking` - Toggle ontology linking
  - `linker_config` - Per-ontology linker configuration

### Telemetry

- `ClinicalNerEx.Telemetry` module with events:
  - `[:clinical_ner_ex, :extract, :start]` - Extraction started
  - `[:clinical_ner_ex, :extract, :stop]` - Extraction completed
  - `[:clinical_ner_ex, :extract, :exception]` - Extraction failed
  - `[:clinical_ner_ex, :linker, :cache_hit]` - Linker cache hit
  - `[:clinical_ner_ex, :linker, :cache_miss]` - Linker cache miss

### Examples

- `examples/basic_extraction.exs` - Basic usage examples
- `examples/cvl_integration.exs` - CVL agent integration examples

### Testing

- Full test suite for all modules
- Integration tests for complete pipeline
- Entity-specific extraction tests

### Entity Types Supported

- `:medication` - Drug names, doses, frequencies, routes (RxNorm linking)
- `:lab_value` - Lab tests, values, units, reference ranges (LOINC linking)
- `:diagnosis` - Diseases, conditions, symptoms (SNOMED-CT, ICD-10 linking)
- `:procedure` - Medical procedures, surgeries (SNOMED-CT linking)
- `:temporal` - Dates, times, durations

### Extraction Methods

- `:rule_based` - Fast regex/pattern matching (fully implemented)
- `:transformer` - Bumblebee model inference (stub for future implementation)
- `:hybrid` - Combined approach (uses rule_based, transformer to be added)

### Notes

This release provides a fully functional rule-based extraction pipeline with:
- Parallel extraction for multiple entity types
- Overlap resolution and deduplication
- Confidence scoring and filtering
- Ontology linking integration (requires med_ontology_ex)

Transformer-based extraction is stubbed and will be implemented in a future release
using Bumblebee with Bio_ClinicalBERT or Med7 models.

[Unreleased]: https://github.com/medlum/clinical_ner_ex/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/medlum/clinical_ner_ex/releases/tag/v0.1.0
