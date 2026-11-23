import Config

# Development-specific configuration
config :clinical_ner_ex,
  # Use rule-based by default in dev for faster iteration
  default_method: :rule_based

# Configure logger for development
config :logger, :console,
  format: "[$level] $message\n",
  level: :debug
