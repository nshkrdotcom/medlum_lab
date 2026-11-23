import Config

# Test configuration
#
# Uses mocked backends by default. Integration tests use real Ollama.

config :logger, level: :warning

# Use mock embedder/chat for unit tests
# Integration tests override this via setup
config :medlum_llm,
  profile: :test,
  enable_eval: true,
  chat_backend: MedlumLlm.ChatMock,
  embed_backend: MedlumLlm.EmbedderMock

# Mock NSAI libraries in tests
config :medlum_llm, :hf_datasets_module, HfDatasetsExMock
config :medlum_llm, :eval_ex_module, EvalExMock
