# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
import Config

# Default configuration for clinical_ner_ex
config :clinical_ner_ex,
  # Default extraction method
  default_method: :hybrid,

  # Confidence thresholds per entity type
  confidence_thresholds: %{
    medication: 0.8,
    lab_value: 0.75,
    diagnosis: 0.7,
    procedure: 0.7,
    temporal: 0.9
  },

  # Per-entity-type method overrides
  entity_methods: %{
    medication: :hybrid,
    lab_value: :hybrid,
    diagnosis: :transformer,
    procedure: :hybrid,
    temporal: :rule_based
  },

  # Performance tuning
  extraction_timeout_ms: 500,
  batch_size: 32,
  max_concurrent_extractions: 4,

  # Ontology linking
  enable_ontology_linking: true,
  linker_config: %{
    rxnorm: %{enabled: true, max_candidates: 5},
    loinc: %{enabled: true, max_candidates: 3},
    snomed: %{enabled: true, max_candidates: 5},
    icd10: %{enabled: true, max_candidates: 3}
  },

  # Model configuration
  models: %{
    clinical_bert_ner: %{
      repo: "emilyalsentzer/Bio_ClinicalBERT",
      task: :token_classification,
      lazy_load: true
    }
  }

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
