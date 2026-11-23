# Development configuration
import Config

# Use a local cache directory for development
config :med_ontology_ex,
  cache_dir: Path.expand("../priv/cache", __DIR__),
  cache_warmup_on_start: false

# Enable sync for development (useful for testing API integration)
config :med_ontology_ex,
  sync_enabled: false

# More verbose logging in development
config :logger, level: :debug
