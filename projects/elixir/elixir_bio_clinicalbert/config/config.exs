import Config

# Default configuration for ElixirBioClinicalbert

config :elixir_bio_clinicalbert,
  # Ollama server URL
  ollama_host: System.get_env("OLLAMA_HOST", "http://localhost:11434"),

  # Embedding model to use
  # Options:
  #   - "nomic-embed-text" (default, general purpose)
  #   - "mxbai-embed-large" (higher quality)
  #   - "hf.co/user/Bio_ClinicalBERT-GGUF:Q4_K_M" (if GGUF version exists)
  model: System.get_env("EMBEDDING_MODEL", "nomic-embed-text")

# Import environment-specific config
import_config "#{config_env()}.exs"
