import Config

# Production-specific configuration
config :clinical_ner_ex,
  # Use hybrid for best accuracy in production
  default_method: :hybrid,
  # Enable ontology linking
  enable_ontology_linking: true,
  # Production timeout
  extraction_timeout_ms: 500

# Configure logger for production
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  level: :info
