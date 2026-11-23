import Config

# Production configuration

config :logger, level: :info

# Production profile with optimized settings
config :medlum_llm,
  profile: :prod_interactive,
  # Disable eval infrastructure in production by default
  # Enable explicitly if needed for production benchmarking
  enable_eval: false
