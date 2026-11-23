import Config

# Development configuration

config :elixir_bio_clinicalbert,
  ollama_host: "http://localhost:11434",
  model: "nomic-embed-text"

config :logger, level: :debug
