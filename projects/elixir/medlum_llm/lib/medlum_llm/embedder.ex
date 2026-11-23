defmodule MedlumLlm.Embedder do
  @moduledoc """
  Clinical text embedding functionality.

  This module generates vector embeddings for medical/clinical text using
  Ollama embedding models. Embeddings can be used for:

  - Semantic search over clinical notes
  - Finding similar patient cases
  - Document clustering by specialty
  - ICD-10 code suggestion
  - Clinical concept similarity

  ## Supported Models

  - `:nomic_embed` - nomic-embed-text (768 dimensions, default)
  - `:mxbai_embed` - mxbai-embed-large (1024 dimensions)

  ## Usage

      # Single embedding
      {:ok, embedding} = MedlumLlm.Embedder.embed("acute chest pain")

      # Batch embeddings
      {:ok, embeddings} = MedlumLlm.Embedder.embed_batch(["text1", "text2"])

      # Similarity between clinical terms
      {:ok, sim} = MedlumLlm.Embedder.similarity("heart attack", "MI")

  """

  alias MedlumLlm.Models

  require Logger

  @doc """
  Generate an embedding vector for a single text.

  ## Options

    * `:model` - Embedding model to use (default: :nomic_embed)
    * `:host` - Ollama host URL

  ## Examples

      {:ok, embedding} = MedlumLlm.Embedder.embed("patient with dyspnea")
      length(embedding)
      # => 768

  """
  @spec embed(String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  def embed(text, opts \\ []) do
    with {:ok, response} <- do_embed([text], opts) do
      case response["embeddings"] do
        [embedding | _] -> {:ok, embedding}
        _ -> {:error, :no_embeddings_returned}
      end
    end
  end

  @doc """
  Generate embeddings for multiple texts in batch.

  More efficient than calling `embed/2` multiple times for large batches.

  ## Examples

      texts = ["myocardial infarction", "diabetes mellitus", "hypertension"]
      {:ok, embeddings} = MedlumLlm.Embedder.embed_batch(texts)
      length(embeddings)
      # => 3

  """
  @spec embed_batch([String.t()], keyword()) :: {:ok, [[float()]]} | {:error, term()}
  def embed_batch(texts, opts \\ []) do
    with {:ok, response} <- do_embed(texts, opts) do
      {:ok, response["embeddings"]}
    end
  end

  @doc """
  Calculate cosine similarity between two clinical texts.

  Returns a float between -1 and 1:
  - 1.0 = identical meaning
  - 0.0 = unrelated
  - -1.0 = opposite meaning

  ## Examples

      # Synonymous medical terms
      {:ok, sim} = MedlumLlm.Embedder.similarity("heart attack", "myocardial infarction")
      # => {:ok, 0.89}

      # Unrelated conditions
      {:ok, sim} = MedlumLlm.Embedder.similarity("diabetes", "broken arm")
      # => {:ok, 0.23}

  """
  @spec similarity(String.t(), String.t(), keyword()) :: {:ok, float()} | {:error, term()}
  def similarity(text1, text2, opts \\ []) do
    with {:ok, emb1} <- embed(text1, opts),
         {:ok, emb2} <- embed(text2, opts) do
      {:ok, MedlumLlm.cosine_similarity(emb1, emb2)}
    end
  end

  @doc """
  Find the most similar texts from a corpus given a query.

  Returns texts sorted by similarity score (highest first).

  ## Examples

      corpus = ["chest pain", "leg fracture", "cardiac arrest", "headache"]
      {:ok, results} = MedlumLlm.Embedder.find_similar("heart attack", corpus, top_k: 2)
      # => {:ok, [{"cardiac arrest", 0.85}, {"chest pain", 0.72}]}

  """
  @spec find_similar(String.t(), [String.t()], keyword()) ::
          {:ok, [{String.t(), float()}]} | {:error, term()}
  def find_similar(query, corpus, opts \\ []) do
    top_k = Keyword.get(opts, :top_k, 5)

    with {:ok, query_emb} <- embed(query, opts),
         {:ok, corpus_embs} <- embed_batch(corpus, opts) do
      results =
        corpus
        |> Enum.zip(corpus_embs)
        |> Enum.map(fn {text, emb} ->
          {text, MedlumLlm.cosine_similarity(query_emb, emb)}
        end)
        |> Enum.sort_by(&elem(&1, 1), :desc)
        |> Enum.take(top_k)

      {:ok, results}
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp do_embed(texts, opts) do
    client = get_client(opts)
    model = get_model(opts)

    Logger.debug("Generating embeddings for #{length(texts)} texts using #{model}")

    Ollixir.embed(client,
      model: model,
      input: texts
    )
  end

  defp get_client(opts) do
    host = Keyword.get(opts, :host, MedlumLlm.get_config(:ollama_host, "http://localhost:11434"))
    Ollixir.init(host)
  end

  defp get_model(opts) do
    model = Keyword.get(opts, :model, :nomic_embed)
    Models.resolve(model)
  end
end
