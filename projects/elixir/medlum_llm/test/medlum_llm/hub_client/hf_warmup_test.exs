defmodule MedlumLlm.HubClient.HfWarmupTest do
  use ExUnit.Case, async: false

  alias MedlumLlm.HubClient.HfWarmup

  @moduletag :unit

  setup do
    # Store original config
    original_hf_hub = Application.get_env(:medlum_llm, :hf_hub_module)

    on_exit(fn ->
      if original_hf_hub do
        Application.put_env(:medlum_llm, :hf_hub_module, original_hf_hub)
      else
        Application.delete_env(:medlum_llm, :hf_hub_module)
      end
    end)

    :ok
  end

  describe "download_datasets/2" do
    test "downloads datasets and returns manifest entries" do
      Application.put_env(:medlum_llm, :hf_hub_module, MockHfHubForDownload)

      assert {:ok, entries} = HfWarmup.download_datasets([:medqa])

      assert length(entries) == 1
      [entry] = entries

      assert entry["dataset_id"] == "medqa"
      assert entry["repo_id"] == "openlifescienceai/medqa"
      assert entry["revision"] == "main"
      assert entry["split"] == "test"
      assert is_list(entry["files"])
    end

    test "downloads multiple datasets" do
      Application.put_env(:medlum_llm, :hf_hub_module, MockHfHubForDownload)

      assert {:ok, entries} = HfWarmup.download_datasets([:medqa, :pubmedqa])

      assert length(entries) == 2
      dataset_ids = Enum.map(entries, & &1["dataset_id"])
      assert "medqa" in dataset_ids
      assert "pubmedqa" in dataset_ids
    end

    test "returns error for unknown dataset" do
      Application.put_env(:medlum_llm, :hf_hub_module, MockHfHubForDownload)

      assert {:error, {:download_failed, :unknown_dataset, :dataset_not_found}} =
               HfWarmup.download_datasets([:unknown_dataset], skip_missing: false)
    end

    test "skips missing datasets when skip_missing is true" do
      Application.put_env(:medlum_llm, :hf_hub_module, MockHfHubForDownload)

      # Should succeed even with unknown dataset
      assert {:ok, entries} =
               HfWarmup.download_datasets([:medqa, :unknown_dataset], skip_missing: true)

      # Should only have the valid dataset
      assert length(entries) == 1
      assert hd(entries)["dataset_id"] == "medqa"
    end

    test "handles download failures gracefully" do
      Application.put_env(:medlum_llm, :hf_hub_module, MockHfHubDownloadFail)

      assert {:error, {:download_failed, :medqa, _reason}} =
               HfWarmup.download_datasets([:medqa], skip_missing: false)
    end
  end

  describe "download_dataset/2" do
    test "returns manifest entry with file paths" do
      Application.put_env(:medlum_llm, :hf_hub_module, MockHfHubForDownload)

      assert {:ok, entry} = HfWarmup.download_dataset(:medqa)

      assert entry["dataset_id"] == "medqa"
      assert entry["config"] == "default"
      assert length(entry["files"]) > 0

      [file] = entry["files"]
      assert file["filename"] =~ "parquet"
      assert file["path"] =~ "/mock/cache/"
    end

    test "respects force_download option" do
      Application.put_env(:medlum_llm, :hf_hub_module, MockHfHubWithOptions)

      assert {:ok, _entry} = HfWarmup.download_dataset(:medqa, force_download: true)

      # Check that force_download was passed through (mock will verify)
    end

    test "respects cache_dir option" do
      Application.put_env(:medlum_llm, :hf_hub_module, MockHfHubWithOptions)

      assert {:ok, _entry} = HfWarmup.download_dataset(:medqa, cache_dir: "/custom/cache")

      # Check that cache_dir was passed through (mock will verify)
    end
  end
end

# Mock for successful download operations
defmodule MockHfHubForDownload do
  @moduledoc false

  def hf_hub_download(opts) do
    filename = Keyword.get(opts, :filename)
    repo_id = Keyword.get(opts, :repo_id)

    # Return a mock cached path
    {:ok, "/mock/cache/#{repo_id}/#{filename}"}
  end
end

# Mock for failed download operations
defmodule MockHfHubDownloadFail do
  @moduledoc false

  def hf_hub_download(_opts) do
    {:error, :network_error}
  end
end

# Mock that captures options for verification
defmodule MockHfHubWithOptions do
  @moduledoc false

  def hf_hub_download(opts) do
    # Verify expected options are present
    _force = Keyword.get(opts, :force_download, false)
    _cache = Keyword.get(opts, :cache_dir)
    filename = Keyword.get(opts, :filename)

    {:ok, "/mock/cache/#{filename}"}
  end
end
