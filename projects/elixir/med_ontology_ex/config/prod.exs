# Production configuration
import Config

# Production cache directory
config :med_ontology_ex,
  cache_dir: System.get_env("MED_ONTOLOGY_CACHE_DIR", "/var/lib/med_ontology/cache"),
  cache_warmup_on_start: true

# Sync configuration for production
# Disable by default for air-gapped clinical environments
config :med_ontology_ex,
  sync_enabled: System.get_env("MED_ONTOLOGY_SYNC_ENABLED", "false") == "true",
  sync_interval_hours: String.to_integer(System.get_env("MED_ONTOLOGY_SYNC_INTERVAL", "24"))

# Production-appropriate logging
config :logger, level: :info
