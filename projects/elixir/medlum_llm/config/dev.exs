import Config

# Development configuration
#
# Enables debug logging and uses local Ollama instance.

config :logger, level: :debug

# Development profile with fast models for rapid iteration
config :medlum_llm,
  profile: :dev_fast,
  enable_eval: true

# You can override models for development:
# config :medlum_llm,
#   chat_model: "hf.co/MoMonir/Llama3-OpenBioLLM-8B-GGUF"
