defmodule MedlumLlm.Embedder.Behaviour do
  @moduledoc """
  Behaviour for embedding backends.
  """

  @type embedding :: [float()]
  @type opts :: keyword()

  @callback embed(String.t(), opts()) :: {:ok, embedding()} | {:error, term()}
  @callback embed_batch([String.t()], opts()) :: {:ok, [embedding()]} | {:error, term()}
  @callback similarity(String.t(), String.t(), opts()) :: {:ok, float()} | {:error, term()}
  @callback find_similar(String.t(), [String.t()], opts()) ::
              {:ok, [{String.t(), float()}]} | {:error, term()}
end
