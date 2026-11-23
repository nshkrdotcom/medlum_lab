import Config

# Test-specific configuration
config :clinical_ner_ex,
  # Use rule-based in tests for speed and determinism
  default_method: :rule_based,
  # Disable ontology linking in tests by default
  enable_ontology_linking: false

# Configure logger for tests
config :logger, :console,
  format: "[$level] $message\n",
  level: :warning
