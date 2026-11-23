import Config

# MedlumLlm Configuration
#
# This file contains the default configuration for all environments.
# Environment-specific overrides are in dev.exs, test.exs, and prod.exs.

config :medlum_llm,
  # Ollama server URL
  ollama_host: System.get_env("OLLAMA_HOST", "http://localhost:11434"),

  # Default chat model (text generation)
  # Options: :biomistral_7b, :openbio_8b, :meditron_7b
  # Or use full HuggingFace path: "hf.co/BioMistral/BioMistral-7B-GGUF"
  chat_model: System.get_env("MEDLUM_CHAT_MODEL", "hf.co/BioMistral/BioMistral-7B-GGUF"),

  # Default embedding model
  # Options: :nomic_embed, :mxbai_embed
  # Or use model name: "nomic-embed-text", "mxbai-embed-large"
  embed_model: System.get_env("MEDLUM_EMBED_MODEL", "nomic-embed-text"),

  # Deployment profile
  # Options: :dev_fast, :dev_full, :test, :prod_interactive, :prod_batch, :prod_critical
  profile: :dev_fast,

  # NSAI Evaluation Configuration
  # Enable/disable evaluation infrastructure (Task.Supervisor for eval workloads)
  enable_eval: true,

  # Default retention policy for evaluation results
  # Options: :all, :errors_only, :none
  eval_default_retention: :errors_only,

  # Directory for evaluation results
  eval_results_dir: "results/"

# Logger configuration
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment-specific config
import_config "#{config_env()}.exs"
