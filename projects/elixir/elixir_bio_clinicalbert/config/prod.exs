import Config

# Production configuration

config :elixir_bio_clinicalbert,
  ollama_host: System.get_env("OLLAMA_HOST", "http://localhost:11434"),
  model: System.get_env("EMBEDDING_MODEL", "nomic-embed-text")

config :logger, level: :info
