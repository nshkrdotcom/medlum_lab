defmodule MedlumLlm.HubClient.HfWarmup do
  @moduledoc """
  HuggingFace dataset warmup for offline deployment.

  Downloads required dataset files from HuggingFace Hub using `HfHub.Download`
  and records the cached paths in the manifest for offline verification.

  ## Architecture

  - Uses `MedlumLlm.Datasets.Config` to get dataset metadata
  - Downloads files via `HfHub.Download.hf_hub_download/1`
  - Records cached file paths for offline verification

  """

  alias MedlumLlm.Datasets.Config

  @doc """
  Downloads multiple datasets and returns manifest entries.

  ## Options

    * `:cache_dir` - Override HuggingFace cache directory
    * `:force_download` - Force re-download even if cached (default: false)
    * `:skip_missing` - Continue on missing datasets instead of failing (default: true)

  ## Returns

    * `{:ok, entries}` - List of manifest entries for downloaded datasets
    * `{:error, reason}` - Download failed

  ## Examples

      {:ok, entries} = HfWarmup.download_datasets([:medqa, :pubmedqa])

  """
  @spec download_datasets([atom()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def download_datasets(dataset_ids, opts \\ []) do
    skip_missing = Keyword.get(opts, :skip_missing, true)

    results =
      Enum.map(dataset_ids, fn dataset_id ->
        download_dataset(dataset_id, opts)
      end)

    # Collect errors and successes
    {successes, failures} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        {:error, _} -> false
      end)

    cond do
      failures == [] ->
        entries = Enum.map(successes, fn {:ok, entry} -> entry end)
        {:ok, entries}

      skip_missing ->
        # Log warnings but continue
        for {:error, reason} <- failures do
          log_warning("Dataset download skipped: #{inspect(reason)}")
        end

        entries = Enum.map(successes, fn {:ok, entry} -> entry end)
        {:ok, entries}

      true ->
        # Return first error
        [{:error, {dataset_id, reason}} | _] = failures
        {:error, {:download_failed, dataset_id, reason}}
    end
  end

  @doc """
  Downloads a single dataset and returns a manifest entry.

  ## Options

    * `:cache_dir` - Override HuggingFace cache directory
    * `:force_download` - Force re-download even if cached

  """
  @spec download_dataset(atom(), keyword()) :: {:ok, map()} | {:error, {atom(), term()}}
  def download_dataset(dataset_id, opts \\ []) do
    case Config.get(dataset_id) do
      {:ok, config} ->
        do_download_dataset(dataset_id, config, opts)

      {:error, :not_found} ->
        {:error, {dataset_id, :dataset_not_found}}
    end
  end

  # Private implementation

  defp do_download_dataset(dataset_id, config, opts) do
    repo = config.repo
    revision = config.revision
    hf_config = config.hf_config
    split = config.default_split
    files = Map.get(config, :files, [])

    # Download each file
    file_results =
      Enum.map(files, fn filename ->
        download_file(repo, filename, revision, opts)
      end)

    # Check for failures
    {successes, failures} =
      Enum.split_with(file_results, fn
        {:ok, _} -> true
        {:error, _} -> false
      end)

    case failures do
      [] ->
        file_entries = Enum.map(successes, fn {:ok, entry} -> entry end)

        manifest_entry = %{
          "dataset_id" => Atom.to_string(dataset_id),
          "repo_id" => repo,
          "revision" => revision,
          "config" => hf_config || "default",
          "split" => split,
          "files" => file_entries
        }

        {:ok, manifest_entry}

      [{:error, reason} | _] ->
        {:error, {dataset_id, reason}}
    end
  end

  defp download_file(repo, filename, revision, opts) do
    download_opts =
      [
        repo_id: repo,
        filename: filename,
        repo_type: :dataset,
        revision: revision
      ]
      |> maybe_add_opt(:cache_dir, opts)
      |> maybe_add_opt(:force_download, opts)

    case hf_hub_module().hf_hub_download(download_opts) do
      {:ok, path} ->
        {:ok, %{"filename" => filename, "path" => path}}

      {:error, reason} ->
        {:error, {:download_failed, filename, reason}}
    end
  end

  defp maybe_add_opt(download_opts, key, opts) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> Keyword.put(download_opts, key, value)
      :error -> download_opts
    end
  end

  defp log_warning(message) do
    require Logger
    Logger.warning("[HfWarmup] #{message}")
  end

  # Module injection for testing
  defp hf_hub_module do
    Application.get_env(:medlum_llm, :hf_hub_module, HfHub.Download)
  end
end
