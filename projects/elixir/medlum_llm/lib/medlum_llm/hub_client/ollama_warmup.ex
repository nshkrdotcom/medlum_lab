defmodule MedlumLlm.HubClient.OllamaWarmup do
  @moduledoc """
  Ollama model warmup for offline deployment.

  Pulls required Ollama models using `Ollixir.pull/2` and verifies
  their availability using `Ollixir.show/2`.

  ## Architecture

  - Models are pulled via Ollama's native API (not as raw GGUF files)
  - Uses `ollama_name` from `MedlumLlm.Models.Registry` for exact model references
  - Does not invent quantization tags; uses whatever is configured in the registry

  """

  alias MedlumLlm.Models.Registry

  @doc """
  Pulls multiple Ollama models and returns manifest entries.

  ## Options

    * `:host` - Ollama host URL (default: "http://localhost:11434")
    * `:timeout` - Pull timeout in milliseconds (default: 600_000 = 10 minutes)

  ## Returns

    * `{:ok, entries}` - List of manifest entries for pulled models
    * `{:error, reason}` - Pull failed

  ## Examples

      {:ok, entries} = OllamaWarmup.pull_models([:biomistral_7b, :nomic_embed])

  """
  @spec pull_models([atom()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def pull_models(model_ids, opts \\ []) do
    host = Keyword.get(opts, :host, "http://localhost:11434")
    client = ollixir_module().init(host)

    results =
      Enum.map(model_ids, fn model_id ->
        pull_model(client, model_id, opts)
      end)

    # Collect errors and successes
    {successes, failures} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        {:error, _} -> false
      end)

    case failures do
      [] ->
        entries = Enum.map(successes, fn {:ok, entry} -> entry end)
        {:ok, entries}

      _ ->
        # Return first error with context
        [{:error, {model_id, reason}} | _] = failures
        {:error, {:pull_failed, model_id, reason}}
    end
  end

  @doc """
  Pulls a single Ollama model and returns a manifest entry.

  ## Options

    * `:timeout` - Pull timeout in milliseconds

  """
  @spec pull_model(term(), atom(), keyword()) :: {:ok, map()} | {:error, {atom(), term()}}
  def pull_model(client, model_id, opts \\ []) do
    case Registry.get(model_id) do
      {:ok, model} ->
        do_pull_model(client, model_id, model, opts)

      {:error, :not_found} ->
        {:error, {model_id, :model_not_found}}
    end
  end

  # Private implementation

  defp do_pull_model(client, model_id, model, _opts) do
    ollama_name = model.ollama_name

    if ollama_name == nil do
      # Skip non-Ollama models (e.g., HuggingFace NER models)
      {:error, {model_id, :not_ollama_model}}
    else
      # Pull the model
      case ollixir_module().pull(client, name: ollama_name) do
        {:ok, _pull_result} ->
          # Verify by getting model info
          verify_and_build_entry(client, model_id, ollama_name)

        {:error, reason} ->
          {:error, {model_id, reason}}
      end
    end
  end

  defp verify_and_build_entry(client, model_id, ollama_name) do
    case ollixir_module().show(client, name: ollama_name) do
      {:ok, info} ->
        entry = build_manifest_entry(model_id, ollama_name, info)
        {:ok, entry}

      {:error, reason} ->
        {:error, {model_id, {:verify_failed, reason}}}
    end
  end

  defp build_manifest_entry(model_id, ollama_name, info) do
    # Extract non-PHI metadata from Ollixir.show response
    safe_info = sanitize_model_info(info)

    %{
      "model_id" => Atom.to_string(model_id),
      "name" => ollama_name,
      "info" => safe_info
    }
  end

  defp sanitize_model_info(info) when is_map(info) do
    # Keep only safe metadata fields (no PHI concerns for model info,
    # but we filter to known fields for forward compatibility)
    allowed_keys = ["details", "modelfile", "parameters", "template", "license", "system"]

    info
    |> Map.take(allowed_keys)
    |> Map.new(fn {k, v} -> {k, sanitize_model_info(v)} end)
  end

  defp sanitize_model_info(info) when is_list(info) do
    Enum.map(info, &sanitize_model_info/1)
  end

  defp sanitize_model_info(info), do: info

  # Module injection for testing
  defp ollixir_module do
    Application.get_env(:medlum_llm, :ollixir_module, Ollixir)
  end
end
