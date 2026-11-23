defmodule ElixirBioClinicalbert.Embedder do
  @moduledoc """
  Behaviour for clinical text embedding backends.

  This behaviour defines the interface that embedding implementations must follow.
  The default implementation uses Ollixir to connect to Ollama.
  """

  @type embedding :: [float()]
  @type opts :: keyword()

  @doc """
  Generate an embedding vector for a single text.
  """
  @callback embed(text :: String.t(), opts()) :: {:ok, embedding()} | {:error, term()}

  @doc """
  Generate embedding vectors for multiple texts in batch.
  """
  @callback embed_batch(texts :: [String.t()], opts()) :: {:ok, [embedding()]} | {:error, term()}

  @doc """
  Check if the embedding service is healthy and responding.
  """
  @callback health_check(opts()) :: :ok | {:error, term()}

  @doc """
  Get information about the current model.
  """
  @callback model_info(opts()) :: {:ok, map()} | {:error, term()}
end
