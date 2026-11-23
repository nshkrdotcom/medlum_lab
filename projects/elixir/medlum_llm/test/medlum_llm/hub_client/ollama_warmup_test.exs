defmodule MedlumLlm.HubClient.OllamaWarmupTest do
  use ExUnit.Case, async: false

  alias MedlumLlm.HubClient.OllamaWarmup

  @moduletag :unit

  setup do
    # Store original config
    original_ollixir = Application.get_env(:medlum_llm, :ollixir_module)

    on_exit(fn ->
      if original_ollixir do
        Application.put_env(:medlum_llm, :ollixir_module, original_ollixir)
      else
        Application.delete_env(:medlum_llm, :ollixir_module)
      end
    end)

    :ok
  end

  describe "pull_models/2" do
    test "pulls Ollama models and returns manifest entries" do
      Application.put_env(:medlum_llm, :ollixir_module, MockOllixirForPull)

      assert {:ok, entries} = OllamaWarmup.pull_models([:nomic_embed])

      assert length(entries) == 1
      [entry] = entries

      assert entry["model_id"] == "nomic_embed"
      assert entry["name"] == "nomic-embed-text"
      assert is_map(entry["info"])
    end

    test "skips non-Ollama models" do
      Application.put_env(:medlum_llm, :ollixir_module, MockOllixirForPull)

      # openmed_pii_small is a HuggingFace model, not Ollama
      assert {:error, {:pull_failed, :openmed_pii_small, :not_ollama_model}} =
               OllamaWarmup.pull_models([:openmed_pii_small])
    end

    test "returns error for unknown model" do
      Application.put_env(:medlum_llm, :ollixir_module, MockOllixirForPull)

      assert {:error, {:pull_failed, :unknown_model_xyz, :model_not_found}} =
               OllamaWarmup.pull_models([:unknown_model_xyz])
    end

    test "pulls multiple models" do
      Application.put_env(:medlum_llm, :ollixir_module, MockOllixirForPull)

      assert {:ok, entries} = OllamaWarmup.pull_models([:nomic_embed, :biomistral_7b])

      assert length(entries) == 2
      model_ids = Enum.map(entries, & &1["model_id"])
      assert "nomic_embed" in model_ids
      assert "biomistral_7b" in model_ids
    end

    test "fails if any model fails to pull" do
      Application.put_env(:medlum_llm, :ollixir_module, MockOllixirPullFail)

      assert {:error, {:pull_failed, _model_id, _reason}} =
               OllamaWarmup.pull_models([:nomic_embed])
    end
  end

  describe "pull_model/3" do
    test "returns manifest entry for successful pull" do
      Application.put_env(:medlum_llm, :ollixir_module, MockOllixirForPull)

      client = MockOllixirForPull.init("http://localhost:11434")
      assert {:ok, entry} = OllamaWarmup.pull_model(client, :biomistral_7b)

      assert entry["model_id"] == "biomistral_7b"
      assert entry["name"] == "hf.co/BioMistral/BioMistral-7B-GGUF"
      assert is_map(entry["info"])
    end

    test "returns error for model not in registry" do
      Application.put_env(:medlum_llm, :ollixir_module, MockOllixirForPull)

      client = MockOllixirForPull.init("http://localhost:11434")
      assert {:error, {:nonexistent_model, :model_not_found}} =
               OllamaWarmup.pull_model(client, :nonexistent_model)
    end
  end
end

# Mock for successful pull operations
defmodule MockOllixirForPull do
  @moduledoc false

  def init(_host), do: :mock_client

  def pull(_client, opts) do
    name = Keyword.get(opts, :name)

    # Simulate successful pull
    {:ok, %{"status" => "success", "model" => name}}
  end

  def show(_client, opts) do
    name = Keyword.get(opts, :name)

    {:ok,
     %{
       "details" => %{
         "family" => "test",
         "format" => "gguf",
         "parameter_size" => "7B",
         "quantization_level" => "Q4_0"
       },
       "modelfile" => "FROM #{name}",
       "parameters" => "",
       "template" => ""
     }}
  end
end

# Mock for failed pull operations
defmodule MockOllixirPullFail do
  @moduledoc false

  def init(_host), do: :mock_client

  def pull(_client, _opts) do
    {:error, :connection_refused}
  end

  def show(_client, _opts) do
    {:error, :not_found}
  end
end
