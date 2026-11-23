defmodule MedlumLlm.HubClient.WarmupTest do
  use ExUnit.Case, async: false

  alias MedlumLlm.HubClient.{Manifest, Warmup}

  @moduletag :unit

  setup do
    # Create a temporary directory for test manifests
    tmp_dir = Path.join(System.tmp_dir!(), "medlum_warmup_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)
    manifest_path = Path.join(tmp_dir, "test_manifest.json")

    # Store original config
    original_ollixir = Application.get_env(:medlum_llm, :ollixir_module)
    original_hf_hub = Application.get_env(:medlum_llm, :hf_hub_module)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
      # Restore original config
      if original_ollixir do
        Application.put_env(:medlum_llm, :ollixir_module, original_ollixir)
      else
        Application.delete_env(:medlum_llm, :ollixir_module)
      end

      if original_hf_hub do
        Application.put_env(:medlum_llm, :hf_hub_module, original_hf_hub)
      else
        Application.delete_env(:medlum_llm, :hf_hub_module)
      end
    end)

    {:ok, tmp_dir: tmp_dir, manifest_path: manifest_path}
  end

  describe "verify_offline_ready/1" do
    test "returns :no_manifest when manifest doesn't exist", %{manifest_path: manifest_path} do
      assert {:error, :no_manifest} = Warmup.verify_offline_ready(manifest_path: manifest_path)
    end

    test "returns :ready when manifest exists and all resources available", %{
      tmp_dir: tmp_dir,
      manifest_path: manifest_path
    } do
      # Set up mock Ollixir
      Application.put_env(:medlum_llm, :ollixir_module, MockOllixir)

      # Create a test file that the manifest will reference
      test_file_path = Path.join(tmp_dir, "test_dataset.parquet")
      File.write!(test_file_path, "test content")

      # Create manifest with a model and file
      manifest =
        Manifest.new()
        |> Manifest.add_ollama_model(%{
          "model_id" => "test_model",
          "name" => "test/model",
          "info" => %{}
        })
        |> Manifest.add_hf_dataset(%{
          "dataset_id" => "test_dataset",
          "repo_id" => "test/repo",
          "revision" => "main",
          "config" => "default",
          "split" => "test",
          "files" => [%{"filename" => "test.parquet", "path" => test_file_path}]
        })

      :ok = Manifest.write(manifest, manifest_path: manifest_path)

      # Mock should return success for show
      assert {:ok, :ready} = Warmup.verify_offline_ready(manifest_path: manifest_path)
    end

    test "returns missing models when Ollama model not found", %{manifest_path: manifest_path} do
      # Set up mock that returns error
      Application.put_env(:medlum_llm, :ollixir_module, MockOllixirNotFound)

      manifest =
        Manifest.new()
        |> Manifest.add_ollama_model(%{
          "model_id" => "missing_model",
          "name" => "missing/model",
          "info" => %{}
        })

      :ok = Manifest.write(manifest, manifest_path: manifest_path)

      assert {:error, {:missing, %{models: missing_models, files: []}}} =
               Warmup.verify_offline_ready(manifest_path: manifest_path)

      assert "missing/model" in missing_models
    end

    test "returns missing files when HF file not found", %{manifest_path: manifest_path} do
      Application.put_env(:medlum_llm, :ollixir_module, MockOllixir)

      manifest =
        Manifest.new()
        |> Manifest.add_hf_dataset(%{
          "dataset_id" => "test_dataset",
          "repo_id" => "test/repo",
          "revision" => "main",
          "config" => "default",
          "split" => "test",
          "files" => [%{"filename" => "missing.parquet", "path" => "/nonexistent/path.parquet"}]
        })

      :ok = Manifest.write(manifest, manifest_path: manifest_path)

      assert {:error, {:missing, %{models: [], files: missing_files}}} =
               Warmup.verify_offline_ready(manifest_path: manifest_path)

      assert "/nonexistent/path.parquet" in missing_files
    end
  end

  describe "warmup/1 with skip options" do
    test "skip_ollama skips Ollama warmup", %{manifest_path: manifest_path} do
      Application.put_env(:medlum_llm, :hf_hub_module, MockHfHub)

      assert {:ok, manifest} =
               Warmup.warmup(
                 manifest_path: manifest_path,
                 skip_ollama: true,
                 datasets: [:medqa]
               )

      # Should have no Ollama models
      assert manifest["ollama"]["models"] == []
      # Should have HF datasets
      assert length(manifest["hf"]["datasets"]) > 0
    end

    test "skip_hf skips HuggingFace warmup", %{manifest_path: manifest_path} do
      Application.put_env(:medlum_llm, :ollixir_module, MockOllixir)

      assert {:ok, manifest} =
               Warmup.warmup(
                 manifest_path: manifest_path,
                 skip_hf: true,
                 models: [:nomic_embed]
               )

      # Should have Ollama models
      assert length(manifest["ollama"]["models"]) > 0
      # Should have no HF datasets
      assert manifest["hf"]["datasets"] == []
    end

    test "both skips create empty manifest", %{manifest_path: manifest_path} do
      assert {:ok, manifest} =
               Warmup.warmup(
                 manifest_path: manifest_path,
                 skip_ollama: true,
                 skip_hf: true
               )

      assert manifest["ollama"]["models"] == []
      assert manifest["hf"]["datasets"] == []

      # Manifest file should still be created
      assert File.exists?(manifest_path)
    end
  end
end

# Mock modules for testing

defmodule MockOllixir do
  @moduledoc false

  def init(_host), do: :mock_client

  def pull(_client, _opts), do: {:ok, %{"status" => "success"}}

  def show(_client, _opts) do
    {:ok,
     %{
       "details" => %{
         "family" => "test",
         "format" => "gguf",
         "parameter_size" => "7B"
       }
     }}
  end

  def list(_client), do: {:ok, %{"models" => []}}
end

defmodule MockOllixirNotFound do
  @moduledoc false

  def init(_host), do: :mock_client

  def pull(_client, _opts), do: {:error, :not_found}

  def show(_client, _opts), do: {:error, :not_found}

  def list(_client), do: {:ok, %{"models" => []}}
end

defmodule MockHfHub do
  @moduledoc false

  def hf_hub_download(opts) do
    filename = Keyword.get(opts, :filename)
    # Return a fake path
    {:ok, "/mock/cache/#{filename}"}
  end
end
