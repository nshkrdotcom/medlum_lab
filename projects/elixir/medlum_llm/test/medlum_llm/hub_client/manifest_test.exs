defmodule MedlumLlm.HubClient.ManifestTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.HubClient.Manifest

  @moduletag :unit

  describe "path/1" do
    test "returns default path with expansion" do
      path = Manifest.path()
      assert path =~ "medlum_warmup_manifest.json"
      # Path should be expanded (not contain ~)
      refute path =~ "~"
    end

    test "respects cache_dir option" do
      path = Manifest.path(cache_dir: "/custom/cache")
      assert path == "/custom/cache/medlum_warmup_manifest.json"
    end
  end

  describe "new/1" do
    test "creates empty manifest structure" do
      manifest = Manifest.new()

      assert %{
               "ollama" => %{"host" => _, "models" => []},
               "hf" => %{"datasets" => []}
             } = manifest
    end

    test "accepts host option" do
      manifest = Manifest.new(host: "http://custom:11434")
      assert manifest["ollama"]["host"] == "http://custom:11434"
    end
  end

  describe "add_ollama_model/2" do
    test "adds model entry to manifest" do
      manifest = Manifest.new()

      model_entry = %{
        "model_id" => "biomistral_7b",
        "name" => "hf.co/BioMistral/BioMistral-7B-GGUF",
        "info" => %{"details" => %{}}
      }

      updated = Manifest.add_ollama_model(manifest, model_entry)

      assert length(updated["ollama"]["models"]) == 1
      assert hd(updated["ollama"]["models"]) == model_entry
    end

    test "appends multiple models" do
      manifest = Manifest.new()

      entry1 = %{"model_id" => "model1", "name" => "name1", "info" => %{}}
      entry2 = %{"model_id" => "model2", "name" => "name2", "info" => %{}}

      updated =
        manifest
        |> Manifest.add_ollama_model(entry1)
        |> Manifest.add_ollama_model(entry2)

      assert length(updated["ollama"]["models"]) == 2
    end
  end

  describe "add_hf_dataset/2" do
    test "adds dataset entry to manifest" do
      manifest = Manifest.new()

      dataset_entry = %{
        "dataset_id" => "medqa",
        "repo_id" => "openlifescienceai/medqa",
        "revision" => "main",
        "config" => "default",
        "split" => "test",
        "files" => [%{"filename" => "test.parquet", "path" => "/cache/test.parquet"}]
      }

      updated = Manifest.add_hf_dataset(manifest, dataset_entry)

      assert length(updated["hf"]["datasets"]) == 1
      assert hd(updated["hf"]["datasets"]) == dataset_entry
    end
  end

  describe "write/2 and read/1" do
    setup do
      # Create a temporary directory for test manifests
      tmp_dir = Path.join(System.tmp_dir!(), "medlum_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)
      manifest_path = Path.join(tmp_dir, "test_manifest.json")

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      {:ok, tmp_dir: tmp_dir, manifest_path: manifest_path}
    end

    test "roundtrip write and read", %{manifest_path: manifest_path} do
      manifest =
        Manifest.new()
        |> Manifest.add_ollama_model(%{
          "model_id" => "test_model",
          "name" => "test/model",
          "info" => %{"key" => "value"}
        })
        |> Manifest.add_hf_dataset(%{
          "dataset_id" => "test_dataset",
          "repo_id" => "test/repo",
          "revision" => "main",
          "config" => "default",
          "split" => "test",
          "files" => []
        })

      assert :ok = Manifest.write(manifest, manifest_path: manifest_path)
      assert {:ok, read_manifest} = Manifest.read(manifest_path: manifest_path)

      # Check structure preserved
      assert read_manifest["ollama"]["models"] == manifest["ollama"]["models"]
      assert read_manifest["hf"]["datasets"] == manifest["hf"]["datasets"]

      # Check metadata added
      assert read_manifest["version"] == Manifest.version()
      assert read_manifest["generated_at"] != nil
      assert read_manifest["medlum_llm_version"] != nil
    end

    test "read returns error for missing file", %{tmp_dir: tmp_dir} do
      missing_path = Path.join(tmp_dir, "nonexistent.json")
      assert {:error, :not_found} = Manifest.read(manifest_path: missing_path)
    end

    test "creates parent directories if needed", %{tmp_dir: tmp_dir} do
      nested_path = Path.join([tmp_dir, "nested", "dir", "manifest.json"])
      manifest = Manifest.new()

      assert :ok = Manifest.write(manifest, manifest_path: nested_path)
      assert File.exists?(nested_path)
    end
  end

  describe "version/0" do
    test "returns version string" do
      assert is_binary(Manifest.version())
    end
  end
end
