# Changelog

All notable changes to MedlumLlm will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-01-25

### Added

#### Comprehensive NSAI Examples

Complete example suite demonstrating all MedlumLlm functionality:

**Example Files**:
- `examples/datasets_example.exs` - Medical dataset loading and exploration
- `examples/metrics_example.exs` - Medical-specific evaluation metrics
- `examples/benchmark_example.exs` - Benchmark configurations and baselines
- `examples/cvl_example.exs` - Clinical Verification Layer demonstration
- `examples/evaluation_pipeline.exs` - End-to-end evaluation workflow

**Mix Aliases**:
- `mix example.datasets` - Run datasets example
- `mix example.metrics` - Run metrics example
- `mix example.benchmarks` - Run benchmarks example
- `mix example.cvl` - Run CVL example
- `mix example.pipeline` - Run evaluation pipeline example
- `mix examples.nsai` - Run all NSAI examples

#### Clinical Verification Layer (CVL)

5-agent verification system for hallucination detection:

**Agent Behaviour** (`MedlumLlm.CVL.Agent`):
- Behaviour definition for CVL verification agents
- Type specifications for verdicts, evidence, and results
- `aggregate_verdicts/1` helper for combining sub-verdicts
- Source-grounded verification semantics (ENTAILMENT/CONTRADICTION/NEUTRAL)
- Consensus weight system (1.5 for Medication, 1.2 for Lab, etc.)

**Medication Agent** (`MedlumLlm.CVL.MedicationAgent`):
- Highest-weight agent (1.5) for safety-critical medication verification
- Drug name verification against RxNorm
- Dose validation against therapeutic ranges
- Frequency plausibility checks
- Drug-drug interaction detection
- Contraindication warnings
- Regex-based medication extraction (ClinicalNerEx integration planned)
- Source-grounded evidence linking

**Lab Agent** (`MedlumLlm.CVL.LabAgent`):
- Weight 1.2 agent for lab value verification
- Lab test name validation against LOINC
- Value within physiologically possible ranges check
- Unit consistency verification
- Reference range classification (normal, low, high, critical_low, critical_high)
- Critical value flagging

**Ontology Agent** (`MedlumLlm.CVL.OntologyAgent`):
- Weight 1.0 agent for clinical terminology verification
- Diagnosis code validation against SNOMED-CT and ICD-10
- Clinical finding (symptom) verification
- Procedure verification
- Finding-diagnosis relationship validation
- Semantic fit checking against chief complaint

**Temporal Agent** (`MedlumLlm.CVL.TemporalAgent`):
- Weight 0.8 agent for timeline verification (lower weight due to temporal ambiguity)
- Date/time extraction from clinical text
- Relative date parsing ("2 days ago", "yesterday", "last week")
- Duration extraction and validation ("for 3 weeks", "over 2 months")
- Absolute date parsing ("January 15, 2026", "01/15/2026")
- Chronological consistency checking
- Disease progression plausibility validation

**Differential Agent** (`MedlumLlm.CVL.DifferentialAgent`):
- Weight 1.0 agent for symptom-diagnosis mapping verification
- Symptom extraction from clinical text (29 common symptoms)
- Diagnosis extraction with pattern matching and abbreviations
- Symptom-diagnosis support verification
- Red flag detection for critical symptom combinations
- Contradicting symptom detection
- Source-grounded evidence linking

#### Ontology Stubs

**RxNorm Stub** (`MedlumLlm.CVL.RxNormStub`):
- In-memory stub for testing without external dependencies
- Supports 8 common medications: metformin, lisinopril, aspirin, atorvastatin, omeprazole, amlodipine, warfarin, insulin
- Therapeutic ranges, typical frequencies, interactions, contraindications
- Configurable via `:rxnorm_module` for production use with `MedOntologyEx.RxNorm`

**LOINC Stub** (`MedlumLlm.CVL.LOINCStub`):
- In-memory stub for testing without external dependencies
- Supports 15 common lab tests: HbA1c, glucose, hemoglobin, WBC, creatinine, BUN, potassium, sodium, platelets, INR, eGFR, total cholesterol, LDL, HDL, TSH
- Reference ranges, physiological limits, critical thresholds
- Configurable via `:loinc_module` for production use with `MedOntologyEx.LOINC`

**SNOMED Stub** (`MedlumLlm.CVL.SNOMEDStub`):
- In-memory stub for testing without external dependencies
- Supports 20+ common diagnoses: type 1/2 diabetes, hypertension, MI, CHF, pneumonia, CKD, asthma, COPD, atrial fibrillation, stroke
- Supports 20+ clinical findings: chest pain, dyspnea, fever, cough, etc.
- Supports 10+ procedures: CABG, PCI, appendectomy, dialysis, etc.
- SNOMED to ICD-10 mapping
- Finding-diagnosis association checking
- Configurable via `:snomed_module` for production use with `MedOntologyEx.SNOMED`

**ICD-10 Stub** (`MedlumLlm.CVL.ICD10Stub`):
- In-memory stub for testing without external dependencies
- Supports 18+ ICD-10 codes across diabetes, cardiovascular, respiratory, renal categories
- Term-to-code lookup with common abbreviations (MI, CHF, CKD, COPD, CVA)
- Code validation, description, chapter, and category lookup
- Configurable via `:icd10_module` for production use with `MedOntologyEx.ICD10`

**DifferentialDB Stub** (`MedlumLlm.CVL.DifferentialDB`):
- In-memory stub for testing without external dependencies
- Supports 13 common diagnoses with symptom mappings
- Red flag detection for 4 critical symptoms (chest pain, syncope, fever, weakness)
- Configurable via `:differential_db_module` for production use with `MedOntologyEx.DifferentialDB`

#### CVL Training Data Pipeline

Complete integration with Forge for CVL training data generation:

**Pipeline Components**:
- `MedlumLlm.CVL.TrainingPipeline` - Main pipeline definition using Forge DSL
- `MedlumLlm.CVL.EvaluationFailureSource` - Reads evaluation results from JSON files

**Pipeline Stages**:
- `MedlumLlm.CVL.Stages.NormalizeText` - Unicode normalization, whitespace standardization
- `MedlumLlm.CVL.Stages.ClaimExtraction` - Splits text into verifiable claims
- `MedlumLlm.CVL.Stages.NLIPairGenerator` - Creates premise/hypothesis pairs
- `MedlumLlm.CVL.Stages.PIIRedaction` - HIPAA-compliant redaction
- `MedlumLlm.CVL.Stages.AnvilExport` - Exports low-confidence samples to Anvil

**CVL Agent Measurements**:
- `MedlumLlm.CVL.Measurements.MedicationAgent` - RxNorm verification
- `MedlumLlm.CVL.Measurements.LabAgent` - LOINC verification
- `MedlumLlm.CVL.Measurements.OntologyAgent` - SNOMED-CT/ICD-10 verification
- `MedlumLlm.CVL.Measurements.TemporalAgent` - Timeline consistency
- `MedlumLlm.CVL.Measurements.DifferentialAgent` - Symptom-diagnosis mapping

**Consensus & Confidence**:
- `MedlumLlm.CVL.Measurements.AgentConsensus` - Multi-agent voting
- `MedlumLlm.CVL.Measurements.Confidence` - Calibrated confidence scoring

#### CVL Labeling Queue Configuration

Integration with Anvil labeling platform for human annotation:

**Core Labeling Modules**:
- `MedlumLlm.CVL.LabelingSchema` - NLI classification schema definition
- `MedlumLlm.CVL.LabelingQueue` - Anvil queue management
- `MedlumLlm.CVL.SampleLoader` - Forge-to-Anvil sample loading

**Export Pipeline**:
- `MedlumLlm.CVL.ExportPipeline` - Training data export
- `MedlumLlm.CVL.ForgeBridge` - Bidirectional sync

**Schema Management**:
- `MedlumLlm.CVL.SchemaVersions` - Version registry
- `MedlumLlm.CVL.LabelingGuidelines` - Annotation guidance

#### Medical Datasets Wrapper

**Datasets Module** (`MedlumLlm.Datasets`):
- Thin wrapper over hf_datasets_ex for medical datasets
- `load/2` - Load dataset with split, limit, sampling options
- `stream/2` - Stream large datasets with backpressure
- `available/0` - List available medical datasets

**Dataset Configurations** (`MedlumLlm.Datasets.Config`):
- MedQA (USMLE-style questions, 12K samples)
- PubMedQA (binary QA from PubMed, 1K samples)
- MedMCQA (Indian medical entrance, 187K samples)
- ReasonMed (chain-of-thought reasoning, 1.1M samples)
- MMLU-Medical (medical MMLU subjects, ~3K samples)

**Preprocessor** (`MedlumLlm.Datasets.Preprocessor`):
- Medical-specific text normalization
- Unified sample format across datasets

#### Medical Benchmarks and Baselines

**Benchmark Configurations** (`MedlumLlm.Eval.Benchmarks`):
- 7+ benchmark configurations for medical evaluation
- MedQA benchmarks: zero-shot, 5-shot, chain-of-thought
- PubMedQA: binary QA (yes/no/maybe)
- MedMCQA: Indian medical entrance exam questions
- MMLU Medical: medical subjects from MMLU
- CVL hallucination detection benchmark

**Published Baselines** (`MedlumLlm.Eval.Baselines`):
- Published results from GPT-4, Med-PaLM 2, Llama 3, OpenBioLLM, II-Medical, BioMistral, Meditron
- Baseline comparison utilities (+/-5% tolerance)
- Formatted comparison strings for reporting

**Prompt Templates** (`MedlumLlm.Eval.Prompts`):
- Zero-shot MCQ template
- Few-shot MCQ template with examples
- Chain-of-thought MCQ template
- Binary QA template (yes/no/maybe)
- Response parsing for all template types

**Experiment Helpers** (`MedlumLlm.Eval.Experiments`):
- `from_benchmark/2` - Create crucible_harness experiment from benchmark config
- `run_sample/3` - Run evaluation on single sample with timing
- `analyze_results/2` - Aggregate results with confidence intervals

#### Medical Metrics

**Medical Metrics** (`MedlumLlm.Eval.MedicalMetrics`):
- Standard metrics delegated to eval_ex (accuracy, F1, exact_match)
- Confidence intervals delegated to crucible_bench (Wilson CI, McNemar)
- Medical-specific metrics:
  - `medication_accuracy/2` - RxNorm-validated medication accuracy
  - `diagnosis_accuracy/2` - ICD-10-validated diagnosis accuracy
  - `lab_accuracy/2` - LOINC-validated lab value accuracy
  - `hallucination_recall/2` - CVL hallucination detection recall
  - `hallucination_precision/2` - CVL hallucination detection precision
  - `clinical_safety_score/3` - Composite safety metric

#### NSAI Ecosystem Integration

**NSAI Evaluation Stack**:
- `eval_ex` ~> 0.1.5 - Core evaluation metrics (accuracy, F1, BLEU, ROUGE)
- `crucible_bench` ~> 0.4.0 - Statistical testing (Wilson CI, McNemar's test)
- `crucible_harness` ~> 0.3.3 - Experiment orchestration and checkpointing
- `metrics_ex` ~> 0.1.0 - Telemetry and observability

**NSAI Data Stack**:
- `hf_datasets_ex` ~> 0.1.2 - Load medical datasets from HuggingFace
- `datasets_ex` ~> 0.1.0 - Dataset versioning and management
- `labeling_ir` ~> 0.1.0 - Labeling intermediate representation

**NSAI Infrastructure**:
- `hf_hub_ex` ~> 0.1.3 - HuggingFace Hub client
- `embed_ex` ~> 0.1.0 - Multi-provider embeddings abstraction
- `crucible_ensemble` ~> 0.4.1 - Multi-agent voting for CVL consensus
- `llm_guard` ~> 0.3.1 - Input/output guardrails and PII detection

**Medical-Specific (optional)**:
- `med_ontology_ex` ~> 0.1.0 - SNOMED-CT, ICD-10, RxNorm, LOINC lookup (planned)
- `clinical_ner_ex` ~> 0.1.0 - Medical entity extraction (planned)

**Integration Modules**:
- `MedlumLlm.Integration.Error` - Structured error handling for NSAI library failures
- `MedlumLlm.Integration.VersionCheck` - Verify NSAI library compatibility

#### Documentation

- Complete README with all new features
- Getting Started guide (`guides/getting_started.md`)
- CVL guide (`guides/cvl.md`) - comprehensive CVL documentation
- Evaluation guide (`guides/evaluation.md`) - medical benchmarks and metrics
- Datasets guide (`guides/datasets.md`)
- CVL Pipeline guides:
  - `guides/cvl_training_pipeline.md`
  - `guides/cvl_measurements.md`
  - `guides/cvl_labeling.md`
  - `guides/cvl_export.md`
- Hexdocs configuration with module grouping

### Changed

- Updated `mix.exs` with comprehensive hexdocs configuration
- Enhanced moduledocs for all public modules
- Added `mix check.nsai` alias for NSAI library verification

## [0.1.0] - 2026-01-01

### Added

- Core LLM integration via Ollama/Ollixir
- Chat interface (`MedlumLlm.Chat`)
- Embedding interface (`MedlumLlm.Embedder`)
- Model registry with 20+ medical models
- Deployment profiles (dev_fast, dev_full, test, prod_interactive, prod_batch, prod_critical)
- Task-based routing (`MedlumLlm.Router`)
- Provider abstraction (ollama, huggingface, mock)
- HIPAA-compliant guardrails:
  - `MedlumLlm.Guardrails` - Main validation interface
  - `MedlumLlm.Guardrails.Redactor` - PHI redaction with date shifting
  - `MedlumLlm.Guardrails.Audit` - Telemetry-based audit logging
  - `MedlumLlm.Detectors.ClinicalPII` - Tiered PII detection patterns
- Documentation guides for HIPAA compliance and redaction
