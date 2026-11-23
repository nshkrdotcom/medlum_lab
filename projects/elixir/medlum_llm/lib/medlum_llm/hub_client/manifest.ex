defmodule MedlumLlm.HubClient.Manifest do
  @moduledoc """
  JSON manifest read/write for warmup verification.

  Manages the warmup manifest file that records all models and datasets
  prepared during warmup. The manifest is used for offline verification
  to confirm all required resources are available.

  ## Manifest Schema

      %{
        "version" => "1.0",
        "generated_at" => "2026-01-25T00:00:00Z",
        "medlum_llm_version" => "0.2.0",
        "ollama" => %{
          "host" => "http://localhost:11434",
          "models" => [
            %{
              "model_id" => "biomistral_7b",
              "name" => "hf.co/BioMistral/BioMistral-7B-GGUF",
              "info" => %{...}  # Ollixir.show/2 response (non-PHI)
            }
          ]
        },
        "hf" => %{
          "datasets" => [
            %{
              "dataset_id" => "medqa",
              "repo_id" => "openlifescienceai/medqa",
              "revision" => "main",
              "config" => "default",
              "split" => "test",
              "files" => [
                %{"filename" => "data/test-00000-of-00001.parquet", "path" => "/..."}
              ]
            }
          ]
        }
      }

  ## Security

  The manifest contains only metadata (model info, file paths, timestamps).
  No PHI or clinical documents are stored in manifests.

  """

  @manifest_filename "medlum_warmup_manifest.json"
  @manifest_version "1.0"

  @doc """
  Returns the path to the warmup manifest file.

  ## Options

    * `:cache_dir` - Override cache directory

  """
  @spec path(keyword()) :: String.t()
  def path(opts \\ []) do
    cache_dir = get_cache_dir(opts)
    Path.join(cache_dir, @manifest_filename) |> Path.expand()
  end

  @doc """
  Reads the warmup manifest from disk.

  ## Options

    * `:manifest_path` - Override manifest file path

  ## Returns

    * `{:ok, manifest}` - Manifest read successfully
    * `{:error, :not_found}` - Manifest file does not exist
    * `{:error, reason}` - Read or parse error

  """
  @spec read(keyword()) :: {:ok, map()} | {:error, term()}
  def read(opts \\ []) do
    manifest_path = Keyword.get(opts, :manifest_path, path(opts))

    if File.exists?(manifest_path) do
      case File.read(manifest_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, manifest} -> {:ok, manifest}
            {:error, reason} -> {:error, {:parse_error, reason}}
          end

        {:error, reason} ->
          {:error, {:read_error, reason}}
      end
    else
      {:error, :not_found}
    end
  end

  @doc """
  Writes the warmup manifest to disk.

  Ensures the parent directory exists and writes atomically.

  ## Options

    * `:manifest_path` - Override manifest file path

  """
  @spec write(map(), keyword()) :: :ok | {:error, term()}
  def write(manifest, opts \\ []) do
    manifest_path = Keyword.get(opts, :manifest_path, path(opts))

    # Ensure parent directory exists
    parent_dir = Path.dirname(manifest_path)

    case File.mkdir_p(parent_dir) do
      :ok ->
        # Add manifest metadata
        manifest_with_meta =
          manifest
          |> Map.put("version", @manifest_version)
          |> Map.put("generated_at", DateTime.utc_now() |> DateTime.to_iso8601())
          |> Map.put("medlum_llm_version", medlum_llm_version())

        # Write atomically via temp file
        temp_path = manifest_path <> ".tmp"

        case Jason.encode(manifest_with_meta, pretty: true) do
          {:ok, json} ->
            case File.write(temp_path, json) do
              :ok ->
                File.rename(temp_path, manifest_path)

              {:error, reason} ->
                {:error, {:write_error, reason}}
            end

          {:error, reason} ->
            {:error, {:encode_error, reason}}
        end

      {:error, reason} ->
        {:error, {:mkdir_error, reason}}
    end
  end

  @doc """
  Creates a new empty manifest structure.
  """
  @spec new(keyword()) :: map()
  def new(opts \\ []) do
    host = Keyword.get(opts, :host, default_ollama_host())

    %{
      "ollama" => %{
        "host" => host,
        "models" => []
      },
      "hf" => %{
        "datasets" => []
      }
    }
  end

  @doc """
  Adds an Ollama model entry to the manifest.
  """
  @spec add_ollama_model(map(), map()) :: map()
  def add_ollama_model(manifest, model_entry) do
    update_in(manifest, ["ollama", "models"], fn models ->
      models ++ [model_entry]
    end)
  end

  @doc """
  Adds a HuggingFace dataset entry to the manifest.
  """
  @spec add_hf_dataset(map(), map()) :: map()
  def add_hf_dataset(manifest, dataset_entry) do
    update_in(manifest, ["hf", "datasets"], fn datasets ->
      datasets ++ [dataset_entry]
    end)
  end

  @doc """
  Returns the manifest version.
  """
  @spec version() :: String.t()
  def version, do: @manifest_version

  # Private helpers

  defp get_cache_dir(opts) do
    Keyword.get_lazy(opts, :cache_dir, fn ->
      config = Application.get_env(:medlum_llm, :hub_client, [])
      Keyword.get(config, :cache_dir, "~/.cache/medlum")
    end)
  end

  defp default_ollama_host do
    config = Application.get_env(:medlum_llm, :hub_client, [])
    Keyword.get(config, :ollama_host) ||
      Application.get_env(:medlum_llm, :ollama_host, "http://localhost:11434")
  end

  defp medlum_llm_version do
    case Application.spec(:medlum_llm, :vsn) do
      nil -> "0.0.0-dev"
      vsn -> to_string(vsn)
    end
  end
end
