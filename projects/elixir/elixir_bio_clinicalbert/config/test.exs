import Config

# Test configuration

# Tests use mocks by default, so this config is only used for integration tests
config :elixir_bio_clinicalbert,
  ollama_host: "http://localhost:11434",
  model: "nomic-embed-text"

config :logger, level: :warning
