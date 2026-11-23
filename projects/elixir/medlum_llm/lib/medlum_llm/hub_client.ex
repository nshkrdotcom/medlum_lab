defmodule MedlumLlm.HubClient do
  @moduledoc """
  Medlum-owned wrapper for offline edge deployment.

  `HubClient` provides warmup and verification functions for offline medical AI deployment:

  - **Warmup**: Pull required Ollama models and download HuggingFace datasets
  - **Manifest**: Generate non-PHI warmup manifest for reproducibility
  - **Verification**: Verify offline readiness at startup

  ## Usage

      # During warmup (network available)
      {:ok, manifest} = MedlumLlm.HubClient.warmup()

      # At startup (offline verification)
      case MedlumLlm.HubClient.verify_offline_ready() do
        {:ok, :ready} -> IO.puts("System ready for offline operation")
        {:error, {:missing, details}} -> IO.puts("Missing: \#{inspect(details)}")
        {:error, :no_manifest} -> IO.puts("No warmup manifest found")
      end

  ## Architecture

  - Chat/embedding model weights are pulled via **Ollama/Ollixir**, not as GGUF files
  - HuggingFace datasets are downloaded via **hf_hub_ex** for evaluation/benchmark data
  - GGUF discovery/selection remains in `Ollixir.HuggingFace` (not duplicated here)

  ## Configuration

      config :medlum_llm, :hub_client,
        cache_dir: "~/.cache/medlum",
        ollama_host: "http://localhost:11434"

  """

  alias MedlumLlm.HubClient.{Manifest, Warmup}

  @doc """
  Runs warmup to prepare for offline operation.

  Downloads required Ollama models and HuggingFace datasets, then generates
  a warmup manifest for verification.

  ## Options

    * `:models` - List of model IDs to pull (default: models fitting current profile VRAM)
    * `:datasets` - List of dataset IDs to download (default: [:medqa, :pubmedqa, :medmcqa])
    * `:host` - Ollama host override (default: from config)
    * `:manifest_path` - Override manifest file path

  ## Returns

    * `{:ok, manifest}` - Warmup completed successfully
    * `{:error, reason}` - Warmup failed

  ## Examples

      # Warmup with profile defaults
      {:ok, manifest} = MedlumLlm.HubClient.warmup()

      # Warmup specific models and datasets
      {:ok, manifest} = MedlumLlm.HubClient.warmup(
        models: [:biomistral_7b, :nomic_embed],
        datasets: [:medqa]
      )

  """
  @spec warmup(keyword()) :: {:ok, map()} | {:error, term()}
  defdelegate warmup(opts \\ []), to: Warmup

  @doc """
  Verifies that all required models and datasets are available for offline operation.

  Reads the warmup manifest and checks:
  - Each listed Ollama model exists (via `Ollixir.show/2`)
  - Each listed HuggingFace file path exists on disk

  ## Options

    * `:manifest_path` - Override manifest file path

  ## Returns

    * `{:ok, :ready}` - All resources available
    * `{:error, {:missing, details}}` - Some resources are missing
    * `{:error, :no_manifest}` - No warmup manifest found

  ## Examples

      case MedlumLlm.HubClient.verify_offline_ready() do
        {:ok, :ready} ->
          IO.puts("System ready for offline operation")
        {:error, {:missing, %{models: missing_models, files: missing_files}}} ->
          IO.puts("Missing models: \#{inspect(missing_models)}")
          IO.puts("Missing files: \#{inspect(missing_files)}")
        {:error, :no_manifest} ->
          IO.puts("Run warmup first")
      end

  """
  @spec verify_offline_ready(keyword()) :: {:ok, :ready} | {:error, term()}
  defdelegate verify_offline_ready(opts \\ []), to: Warmup

  @doc """
  Returns the path to the warmup manifest file.

  ## Options

    * `:cache_dir` - Override cache directory

  ## Examples

      path = MedlumLlm.HubClient.manifest_path()
      # => "~/.cache/medlum/medlum_warmup_manifest.json"

  """
  @spec manifest_path(keyword()) :: String.t()
  defdelegate manifest_path(opts \\ []), to: Manifest, as: :path
end
