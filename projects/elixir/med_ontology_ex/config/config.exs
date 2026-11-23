# General configuration for med_ontology_ex
import Config

# API Credentials (set via environment variables in production)
config :med_ontology_ex,
  umls_api_key: System.get_env("UMLS_API_KEY"),
  loinc_username: System.get_env("LOINC_USERNAME"),
  loinc_password: System.get_env("LOINC_PASSWORD"),
  who_client_id: System.get_env("WHO_CLIENT_ID"),
  who_client_secret: System.get_env("WHO_CLIENT_SECRET")

# Cache Configuration
config :med_ontology_ex,
  cache_dir: System.get_env("MED_ONTOLOGY_CACHE_DIR", "/var/lib/med_ontology/cache"),
  cache_warmup_on_start: true

# Sync Configuration (disabled by default for air-gapped environments)
config :med_ontology_ex,
  sync_enabled: false,
  sync_interval_hours: 24

# Performance Configuration
config :med_ontology_ex,
  http_timeout_ms: 5_000,
  search_result_limit: 25,
  max_retries: 3,
  retry_delay_ms: 1_000

# Enabled Ontologies
config :med_ontology_ex,
  enabled_ontologies: [:snomed_ct, :icd10, :rxnorm, :loinc]

# Logger configuration
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:ontology, :code]

# Import environment-specific config
import_config "#{config_env()}.exs"
