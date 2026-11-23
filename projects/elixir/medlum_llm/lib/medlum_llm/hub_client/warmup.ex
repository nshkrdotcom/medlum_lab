defmodule MedlumLlm.HubClient.Warmup do
  @moduledoc """
  Warmup orchestrator for offline edge deployment.

  Coordinates the download of Ollama models and HuggingFace datasets,
  then generates a manifest for offline verification.

  ## Architecture

  - Ollama models are pulled via `Ollixir.pull/2` (not as raw GGUF files)
  - HuggingFace datasets are downloaded via `HfHub.Download`
  - The manifest records all pulled resources for verification

  """

  alias MedlumLlm.HubClient.{Manifest, OllamaWarmup, HfWarmup}
  alias MedlumLlm.{Models.Registry, Profile}

  @default_datasets [:medqa, :pubmedqa, :medmcqa]

  @doc """
  Runs warmup to prepare for offline operation.

  ## Options

    * `:models` - List of model IDs to pull (default: models fitting current profile VRAM)
    * `:datasets` - List of dataset IDs to download (default: #{inspect(@default_datasets)})
    * `:host` - Ollama host override
    * `:manifest_path` - Override manifest file path
    * `:skip_ollama` - Skip Ollama model warmup (default: false)
    * `:skip_hf` - Skip HuggingFace dataset warmup (default: false)

  ## Returns

    * `{:ok, manifest}` - Warmup completed successfully
    * `{:error, reason}` - Warmup failed

  """
  @spec warmup(keyword()) :: {:ok, map()} | {:error, term()}
  def warmup(opts \\ []) do
    host = get_ollama_host(opts)
    models = Keyword.get_lazy(opts, :models, &default_models/0)
    datasets = Keyword.get(opts, :datasets, @default_datasets)
    skip_ollama = Keyword.get(opts, :skip_ollama, false)
    skip_hf = Keyword.get(opts, :skip_hf, false)

    manifest = Manifest.new(host: host)

    with {:ok, manifest} <- maybe_warmup_ollama(manifest, models, host, skip_ollama),
         {:ok, manifest} <- maybe_warmup_hf(manifest, datasets, skip_hf),
         :ok <- Manifest.write(manifest, opts) do
      {:ok, manifest}
    end
  end

  @doc """
  Verifies that all required models and datasets are available for offline operation.

  ## Options

    * `:manifest_path` - Override manifest file path
    * `:host` - Ollama host override

  ## Returns

    * `{:ok, :ready}` - All resources available
    * `{:error, {:missing, details}}` - Some resources are missing
    * `{:error, :no_manifest}` - No warmup manifest found

  """
  @spec verify_offline_ready(keyword()) :: {:ok, :ready} | {:error, term()}
  def verify_offline_ready(opts \\ []) do
    case Manifest.read(opts) do
      {:ok, manifest} ->
        verify_manifest(manifest, opts)

      {:error, :not_found} ->
        {:error, :no_manifest}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private: Warmup orchestration

  defp maybe_warmup_ollama(manifest, _models, _host, true), do: {:ok, manifest}

  defp maybe_warmup_ollama(manifest, models, host, false) do
    case OllamaWarmup.pull_models(models, host: host) do
      {:ok, model_entries} ->
        manifest =
          Enum.reduce(model_entries, manifest, fn entry, acc ->
            Manifest.add_ollama_model(acc, entry)
          end)

        {:ok, manifest}

      {:error, reason} ->
        {:error, {:ollama_warmup_failed, reason}}
    end
  end

  defp maybe_warmup_hf(manifest, _datasets, true), do: {:ok, manifest}

  defp maybe_warmup_hf(manifest, datasets, false) do
    case HfWarmup.download_datasets(datasets) do
      {:ok, dataset_entries} ->
        manifest =
          Enum.reduce(dataset_entries, manifest, fn entry, acc ->
            Manifest.add_hf_dataset(acc, entry)
          end)

        {:ok, manifest}

      {:error, reason} ->
        {:error, {:hf_warmup_failed, reason}}
    end
  end

  # Private: Verification

  defp verify_manifest(manifest, opts) do
    host = get_ollama_host(opts)

    missing_models = verify_ollama_models(manifest, host)
    missing_files = verify_hf_files(manifest)

    cond do
      missing_models == [] and missing_files == [] ->
        {:ok, :ready}

      true ->
        {:error, {:missing, %{models: missing_models, files: missing_files}}}
    end
  end

  defp verify_ollama_models(manifest, host) do
    models = get_in(manifest, ["ollama", "models"]) || []

    client = ollixir_module().init(host)

    Enum.reduce(models, [], fn model_entry, missing ->
      name = model_entry["name"]

      case ollixir_module().show(client, name: name) do
        {:ok, _info} -> missing
        {:error, _reason} -> [name | missing]
      end
    end)
  end

  defp verify_hf_files(manifest) do
    datasets = get_in(manifest, ["hf", "datasets"]) || []

    Enum.reduce(datasets, [], fn dataset_entry, missing ->
      files = dataset_entry["files"] || []

      Enum.reduce(files, missing, fn file_entry, acc ->
        path = file_entry["path"]

        if path && File.exists?(path) do
          acc
        else
          [path || file_entry["filename"] | acc]
        end
      end)
    end)
  end

  # Private: Configuration helpers

  defp get_ollama_host(opts) do
    Keyword.get_lazy(opts, :host, fn ->
      config = Application.get_env(:medlum_llm, :hub_client, [])

      Keyword.get(config, :ollama_host) ||
        Application.get_env(:medlum_llm, :ollama_host, "http://localhost:11434")
    end)
  end

  defp default_models do
    max_vram = Profile.max_vram()

    # Get Ollama models that fit in VRAM budget
    Registry.fits_vram(max_vram)
    |> Enum.filter(fn model -> model.provider == :ollama end)
    |> Enum.map(fn model -> model.id end)
  end

  # Module injection for testing
  defp ollixir_module do
    Application.get_env(:medlum_llm, :ollixir_module, Ollixir)
  end
end
