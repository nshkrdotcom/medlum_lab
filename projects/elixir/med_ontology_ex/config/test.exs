# Test configuration
import Config

# Use a temporary directory for test cache
config :med_ontology_ex,
  cache_dir: System.tmp_dir!() |> Path.join("med_ontology_test_cache"),
  cache_warmup_on_start: false

# Disable sync during tests
config :med_ontology_ex,
  sync_enabled: false

# Faster timeouts for tests
config :med_ontology_ex,
  http_timeout_ms: 1_000,
  max_retries: 1,
  retry_delay_ms: 100

# Less verbose logging during tests
config :logger, level: :warning
