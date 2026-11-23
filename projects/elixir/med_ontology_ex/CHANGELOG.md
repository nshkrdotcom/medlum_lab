# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-01-25

### Added

- Initial release of med_ontology_ex
- Core data structures: `Concept`, `Relationship`, `Mapping`, `SearchResult`
- Unified public API via `MedOntology` module
- Ontology-specific modules:
  - `MedOntology.SnomedCT` - SNOMED Clinical Terms
  - `MedOntology.ICD10` - ICD-10 diagnosis codes
  - `MedOntology.RxNorm` - RxNorm medication terminology
  - `MedOntology.LOINC` - LOINC lab codes
- OTP Application with supervision tree
- Cache layer with ETS (memory) and DETS (persistence)
- `MedOntology.Cache.Server` - GenServer for cache management
- `MedOntology.Cache.Warmer` - Cache pre-population
- `MedOntology.Cache.Sync` - Optional background sync
- Cross-ontology mapping via `MedOntology.Mapper`
- Client behaviour for external APIs (`MedOntology.Client`)
- Ontology behaviour for consistent module interfaces (`MedOntology.Ontology`)
- Telemetry integration for observability
- Configuration module for runtime settings
- Code validation for all four ontologies
- Comprehensive documentation with ExDoc

### Features

- **Lookup**: `MedOntology.lookup/3` - Look up concepts by code
- **Search**: `MedOntology.search/3` - Search concepts by text
- **Validation**: `MedOntology.valid?/2` - Validate code format
- **Mapping**: `MedOntology.map/3` - Cross-ontology mapping
- **Hierarchy**: `MedOntology.ancestors/3`, `MedOntology.descendants/3`
- **Batch**: `MedOntology.lookup_batch/3` - Concurrent batch lookups
- **Cache Management**: `MedOntology.warmup/2`, `MedOntology.cache_stats/0`

### Technical Details

- Built on Elixir 1.15+ / OTP 25+
- Uses Finch for HTTP connection pooling
- ETS tables with read_concurrency for fast lookups
- DETS persistence for offline operation
- Telemetry events for monitoring

[Unreleased]: https://github.com/medlum/med_ontology_ex/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/medlum/med_ontology_ex/releases/tag/v0.1.0
