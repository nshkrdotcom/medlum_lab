defmodule ElixirBioClinicalbert.Embedder.Ollixir do
  @moduledoc """
  Ollixir-based implementation of the Embedder behaviour.

  This module connects to Ollama via Ollixir to generate embeddings
  using Bio_ClinicalBERT or compatible clinical embedding models.

  ## Configuration

      config :elixir_bio_clinicalbert,
        ollama_host: "http://localhost:11434",
        model: "nomic-embed-text"

  ## Notes on Bio_ClinicalBERT

  The original Bio_ClinicalBERT (emilyalsentzer/Bio_ClinicalBERT) is a BERT model
  trained on MIMIC-III clinical notes. For use with Ollama, you need either:

  1. A GGUF-converted version of Bio_ClinicalBERT
  2. An alternative clinical embedding model in GGUF format
  3. Use nomic-embed-text as a general-purpose alternative

  For production clinical NLP, consider using specialized medical embedding models.
  """

  @behaviour ElixirBioClinicalbert.Embedder

  require Logger

  @default_model "nomic-embed-text"

  @impl true
  def embed(text, opts \\ []) do
    with {:ok, response} <- do_embed([text], opts) do
      case response["embeddings"] do
        [embedding | _] -> {:ok, embedding}
        _ -> {:error, :no_embeddings_returned}
      end
    end
  end

  @impl true
  def embed_batch(texts, opts \\ []) do
    with {:ok, response} <- do_embed(texts, opts) do
      {:ok, response["embeddings"]}
    end
  end

  @impl true
  def health_check(opts \\ []) do
    client = get_client(opts)

    case Ollixir.list(client) do
      {:ok, _models} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def model_info(opts \\ []) do
    client = get_client(opts)
    model = get_model(opts)

    case Ollixir.show(client, name: model) do
      {:ok, info} ->
        {:ok, %{
          name: model,
          parameters: info["parameters"],
          template: info["template"],
          details: info["details"]
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helpers

  defp do_embed(texts, opts) do
    client = get_client(opts)
    model = get_model(opts)

    Logger.debug("Generating embeddings for #{length(texts)} texts using model: #{model}")

    Ollixir.embed(client,
      model: model,
      input: texts
    )
  end

  defp get_client(opts) do
    host = Keyword.get(opts, :host, get_config(:ollama_host, "http://localhost:11434"))
    Ollixir.init(host)
  end

  defp get_model(opts) do
    Keyword.get(opts, :model, get_config(:model, @default_model))
  end

  defp get_config(key, default) do
    Application.get_env(:elixir_bio_clinicalbert, key, default)
  end
end
