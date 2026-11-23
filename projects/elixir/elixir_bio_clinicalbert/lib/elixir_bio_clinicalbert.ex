defmodule ElixirBioClinicalbert do
  @moduledoc """
  Clinical text embedding using Bio_ClinicalBERT via Ollixir.

  This module provides clinical NLP capabilities using the Bio_ClinicalBERT model
  (https://huggingface.co/emilyalsentzer/Bio_ClinicalBERT) through Ollama/Ollixir.

  ## Usage

      # Get embeddings for clinical text
      {:ok, embeddings} = ElixirBioClinicalbert.embed("Patient presents with acute chest pain")

      # Calculate similarity between clinical texts
      {:ok, similarity} = ElixirBioClinicalbert.similarity(
        "acute myocardial infarction",
        "heart attack"
      )

  ## Configuration

  Configure the Ollama host in your config:

      config :elixir_bio_clinicalbert,
        ollama_host: "http://localhost:11434",
        model: "nomic-embed-text"  # or Bio_ClinicalBERT GGUF when available
  """

  alias ElixirBioClinicalbert.Embedder

  @doc """
  Generate embeddings for clinical text.

  ## Examples

      iex> {:ok, embeddings} = ElixirBioClinicalbert.embed("chest pain")
      iex> is_list(embeddings)
      true

  """
  @spec embed(String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  def embed(text, opts \\ []) do
    embedder().embed(text, opts)
  end

  @doc """
  Generate embeddings for multiple clinical texts in batch.

  ## Examples

      iex> {:ok, embeddings} = ElixirBioClinicalbert.embed_batch(["chest pain", "dyspnea"])
      iex> length(embeddings) == 2
      true

  """
  @spec embed_batch([String.t()], keyword()) :: {:ok, [[float()]]} | {:error, term()}
  def embed_batch(texts, opts \\ []) do
    embedder().embed_batch(texts, opts)
  end

  @doc """
  Calculate cosine similarity between two clinical texts.

  Returns a value between -1 and 1, where 1 means identical,
  0 means orthogonal, and -1 means opposite.

  ## Examples

      iex> {:ok, sim} = ElixirBioClinicalbert.similarity("heart attack", "myocardial infarction")
      iex> sim > 0.5
      true

  """
  @spec similarity(String.t(), String.t(), keyword()) :: {:ok, float()} | {:error, term()}
  def similarity(text1, text2, opts \\ []) do
    with {:ok, emb1} <- embed(text1, opts),
         {:ok, emb2} <- embed(text2, opts) do
      {:ok, cosine_similarity(emb1, emb2)}
    end
  end

  @doc """
  Check if the embedding service is available and responding.
  """
  @spec health_check(keyword()) :: :ok | {:error, term()}
  def health_check(opts \\ []) do
    embedder().health_check(opts)
  end

  @doc """
  Get information about the current model being used.
  """
  @spec model_info(keyword()) :: {:ok, map()} | {:error, term()}
  def model_info(opts \\ []) do
    embedder().model_info(opts)
  end

  # Private helpers

  defp embedder do
    Application.get_env(:elixir_bio_clinicalbert, :embedder, Embedder.Ollixir)
  end

  @doc false
  def cosine_similarity(vec_a, vec_b) when length(vec_a) == length(vec_b) do
    dot_product = Enum.zip(vec_a, vec_b) |> Enum.map(fn {a, b} -> a * b end) |> Enum.sum()
    magnitude_a = :math.sqrt(Enum.map(vec_a, &(&1 * &1)) |> Enum.sum())
    magnitude_b = :math.sqrt(Enum.map(vec_b, &(&1 * &1)) |> Enum.sum())

    if magnitude_a == 0 or magnitude_b == 0 do
      0.0
    else
      dot_product / (magnitude_a * magnitude_b)
    end
  end
end
