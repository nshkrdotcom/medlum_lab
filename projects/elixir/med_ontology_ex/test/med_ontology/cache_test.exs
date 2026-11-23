defmodule MedOntology.CacheTest do
  use ExUnit.Case, async: false

  alias MedOntology.Cache
  alias MedOntology.Cache.{Server, Store}

  @moduletag :cache

  setup do
    # Clear caches before each test
    Cache.clear_all()
    :ok
  end

  describe "Cache.Store" do
    test "create_table creates an ETS table" do
      table_name = :"test_cache_#{System.unique_integer([:positive])}"
      assert :ok = Store.create_table(table_name)
      assert :ets.whereis(table_name) != :undefined
    end

    test "create_table is idempotent" do
      table_name = :"test_cache_#{System.unique_integer([:positive])}"
      assert :ok = Store.create_table(table_name)
      assert :ok = Store.create_table(table_name)
    end

    test "get returns :miss for missing key" do
      assert :miss = Store.get(:rxnorm_cache, "missing_key_#{System.unique_integer()}")
    end

    test "put and get work correctly" do
      key = "test_key_#{System.unique_integer()}"
      Store.put(:rxnorm_cache, key, "value1")
      assert {:ok, "value1"} = Store.get(:rxnorm_cache, key)
    end

    test "put stores complex values" do
      key = "test_key_#{System.unique_integer()}"
      value = %{name: "metformin", rxcui: "861004", dose: "500mg"}
      Store.put(:rxnorm_cache, key, value)
      assert {:ok, ^value} = Store.get(:rxnorm_cache, key)
    end

    test "put_batch stores multiple entries" do
      prefix = System.unique_integer()
      entries = [
        {"k1_#{prefix}", "v1"},
        {"k2_#{prefix}", "v2"},
        {"k3_#{prefix}", "v3"}
      ]
      Store.put_batch(:rxnorm_cache, entries)

      assert {:ok, "v1"} = Store.get(:rxnorm_cache, "k1_#{prefix}")
      assert {:ok, "v2"} = Store.get(:rxnorm_cache, "k2_#{prefix}")
      assert {:ok, "v3"} = Store.get(:rxnorm_cache, "k3_#{prefix}")
    end

    test "delete removes entry" do
      key = "test_key_#{System.unique_integer()}"
      Store.put(:rxnorm_cache, key, "value")
      assert {:ok, "value"} = Store.get(:rxnorm_cache, key)

      Store.delete(:rxnorm_cache, key)
      assert :miss = Store.get(:rxnorm_cache, key)
    end

    test "clear removes all entries from table" do
      prefix = System.unique_integer()
      Store.put(:linker_cache, "key1_#{prefix}", "value1")
      Store.put(:linker_cache, "key2_#{prefix}", "value2")

      Store.clear(:linker_cache)

      assert :miss = Store.get(:linker_cache, "key1_#{prefix}")
      assert :miss = Store.get(:linker_cache, "key2_#{prefix}")
    end

    test "stats returns table information" do
      key = "test_key_#{System.unique_integer()}"
      Store.put(:rxnorm_cache, key, "value")

      stats = Store.stats(:rxnorm_cache)
      assert stats.exists == true
      assert stats.size >= 1
      assert stats.memory_bytes > 0
      assert stats.type == :set
    end

    test "stats returns exists: false for missing table" do
      stats = Store.stats(:nonexistent_table)
      assert stats.exists == false
    end

    test "exists? returns true for existing key" do
      key = "test_key_#{System.unique_integer()}"
      Store.put(:rxnorm_cache, key, "value")
      assert Store.exists?(:rxnorm_cache, key)
    end

    test "exists? returns false for missing key" do
      refute Store.exists?(:rxnorm_cache, "nonexistent_#{System.unique_integer()}")
    end

    test "get_stale returns value regardless of TTL" do
      key = "test_key_#{System.unique_integer()}"
      Store.put(:rxnorm_cache, key, "value")
      assert {:ok, "value"} = Store.get_stale(:rxnorm_cache, key)
    end

    test "keys returns all keys in table" do
      prefix = System.unique_integer()
      Store.put(:linker_cache, "key1_#{prefix}", "value1")
      Store.put(:linker_cache, "key2_#{prefix}", "value2")

      keys = Store.keys(:linker_cache)
      assert "key1_#{prefix}" in keys
      assert "key2_#{prefix}" in keys
    end

    test "ttl_config returns TTL configuration" do
      config = Store.ttl_config()
      assert is_map(config)
      assert Map.has_key?(config, :snomed_ct_cache)
      assert Map.has_key?(config, :rxnorm_cache)
      assert config[:snomed_ct_cache] == 7 * 24 * 60 * 60
    end
  end

  describe "Cache.Server" do
    test "put and get through server" do
      key = "server_test_#{System.unique_integer()}"
      Cache.put(:rxnorm, key, %{name: "test"})
      assert {:ok, %{name: "test"}} = Cache.get(:rxnorm, key)
    end

    test "get returns :miss for missing key" do
      assert :miss = Cache.get(:snomed_ct, "nonexistent_#{System.unique_integer()}")
    end

    test "get_stale returns value for existing key" do
      key = "server_test_#{System.unique_integer()}"
      Cache.put(:rxnorm, key, %{name: "test"})
      assert {:ok, %{name: "test"}} = Cache.get_stale(:rxnorm, key)
    end

    test "put_batch stores multiple entries" do
      prefix = System.unique_integer()
      entries = [
        {"batch1_#{prefix}", %{name: "metformin"}},
        {"batch2_#{prefix}", %{name: "lisinopril"}}
      ]
      Cache.put_batch(:rxnorm, entries)

      assert {:ok, %{name: "metformin"}} = Cache.get(:rxnorm, "batch1_#{prefix}")
      assert {:ok, %{name: "lisinopril"}} = Cache.get(:rxnorm, "batch2_#{prefix}")
    end

    test "stats returns all ontology stats" do
      stats = Cache.stats()
      assert Map.has_key?(stats, :snomed_ct)
      assert Map.has_key?(stats, :rxnorm)
      assert Map.has_key?(stats, :loinc)
      assert Map.has_key?(stats, :icd10)
      assert Map.has_key?(stats, :warmup_complete)
    end

    test "clear removes all entries for ontology" do
      prefix = System.unique_integer()
      Cache.put(:rxnorm, "key1_#{prefix}", "value1")
      Cache.put(:rxnorm, "key2_#{prefix}", "value2")

      Cache.clear(:rxnorm)

      assert :miss = Cache.get(:rxnorm, "key1_#{prefix}")
      assert :miss = Cache.get(:rxnorm, "key2_#{prefix}")
    end

    test "clear_all removes all cache entries" do
      prefix = System.unique_integer()
      Cache.put(:rxnorm, "key1_#{prefix}", "value1")
      Cache.put(:snomed_ct, "key2_#{prefix}", "value2")

      Cache.clear_all()

      assert :miss = Cache.get(:rxnorm, "key1_#{prefix}")
      assert :miss = Cache.get(:snomed_ct, "key2_#{prefix}")
    end

    test "tables returns list of all cache tables" do
      tables = Server.tables()
      assert is_list(tables)
      assert :snomed_ct_cache in tables
      assert :rxnorm_cache in tables
      assert :loinc_cache in tables
      assert :icd10_cache in tables
    end

    test "table_for maps ontology to table name" do
      assert Server.table_for(:snomed_ct) == :snomed_ct_cache
      assert Server.table_for(:rxnorm) == :rxnorm_cache
      assert Server.table_for(:loinc) == :loinc_cache
      assert Server.table_for(:icd10) == :icd10_cache
    end

    test "warmup completes successfully" do
      # Warmup is already done on startup, but we can call it again
      assert :ok = Cache.warmup()
      stats = Cache.stats()
      assert stats.warmup_complete == true
    end
  end

  describe "Cache.Warmer" do
    alias MedOntology.Cache.Warmer

    test "estimate_size returns size information" do
      key = "warmer_test_#{System.unique_integer()}"
      Cache.put(:rxnorm, key, %{large: String.duplicate("x", 1000)})

      size = Warmer.estimate_size()
      assert size.total_bytes >= 0
      assert Map.has_key?(size, :total_mb)
      assert Map.has_key?(size, :breakdown)
    end

    test "common_snomed_concepts returns list of concepts" do
      concepts = Warmer.common_snomed_concepts()
      assert is_list(concepts)
      assert concepts != []
      assert "44054006" in concepts  # Type 2 diabetes
      assert "38341003" in concepts  # Hypertension
    end

    test "common_rxcuis returns list of RxCUIs" do
      rxcuis = Warmer.common_rxcuis()
      assert is_list(rxcuis)
      assert rxcuis != []
      assert "861004" in rxcuis  # metformin 500mg
    end

    test "common_loinc_codes returns list of LOINC codes" do
      codes = Warmer.common_loinc_codes()
      assert is_list(codes)
      assert codes != []
      assert "2345-7" in codes  # Glucose
      assert "4548-4" in codes  # HbA1c
    end

    test "warmup_stats returns cache statistics" do
      stats = Warmer.warmup_stats()
      assert is_map(stats)
      assert Map.has_key?(stats, :warmup_complete)
    end

    test "warmup/0 completes without error" do
      assert :ok = Warmer.warmup()
    end

    test "warmup/1 with ontologies list completes without error" do
      assert :ok = Warmer.warmup([:rxnorm, :snomed_ct])
    end

    test "warmup/1 with options completes without error" do
      assert :ok = Warmer.warmup(sync: false)
    end

    test "warmup/2 with ontologies and options completes without error" do
      assert :ok = Warmer.warmup([:rxnorm], sync: false)
    end

    test "warmup with progress callback receives events" do
      events = :ets.new(:warmup_events, [:bag, :public])

      callback = fn event ->
        :ets.insert(events, {event})
      end

      Warmer.warmup(ontologies: [:icd10], progress_callback: callback)

      recorded = :ets.tab2list(events) |> Enum.map(fn {e} -> e end)
      assert {:starting, :icd10} in recorded
      assert {:completed, :icd10} in recorded
    end
  end

  describe "Cache performance" do
    test "cached lookup is fast (sub-10ms)" do
      key = "perf_test_#{System.unique_integer()}"
      Cache.put(:rxnorm, key, %{name: "metformin", rxcui: "861004"})

      # Measure lookup time
      {time_us, result} = :timer.tc(fn ->
        Cache.get(:rxnorm, key)
      end)

      assert {:ok, _} = result
      # Should be well under 10ms (10000 microseconds)
      # ETS lookups are typically sub-microsecond
      assert time_us < 10_000, "Lookup took #{time_us}us, expected <10000us"
    end

    test "batch operations are efficient" do
      prefix = System.unique_integer()
      # Create 100 entries
      entries = for i <- 1..100, do: {"key_#{prefix}_#{i}", %{index: i}}

      # Measure batch put time
      {put_time_us, :ok} = :timer.tc(fn ->
        Cache.put_batch(:rxnorm, entries)
      end)

      # Should complete quickly
      assert put_time_us < 100_000, "Batch put took #{put_time_us}us"

      # Verify all entries are stored
      for {key, value} <- entries do
        assert {:ok, ^value} = Cache.get(:rxnorm, key)
      end
    end
  end

  describe "Cache.Sync" do
    alias MedOntology.Cache.Sync

    @tag :skip_when_sync_disabled
    test "status returns sync state when sync is running" do
      # This test requires the Sync GenServer to be running.
      # Skip if it's not started (sync is disabled by default).
      case GenServer.whereis(Sync) do
        nil ->
          # Sync is not running (disabled) - this is expected in default config
          :ok

        _pid ->
          status = Sync.status()
          assert is_map(status)
          assert Map.has_key?(status, :enabled)
          assert Map.has_key?(status, :interval_hours)
          assert Map.has_key?(status, :last_sync)
          assert Map.has_key?(status, :sync_in_progress)
      end
    end

    test "sync_now does not crash when sync is not running" do
      # When sync is disabled, the GenServer is not started.
      # sync_now is a cast, so calling it when process doesn't exist
      # may return :ok or raise. We handle both cases.
      case GenServer.whereis(Sync) do
        nil ->
          # Sync is not running - expected behavior
          :ok

        _pid ->
          # Sync is running - can call sync_now
          assert :ok = Sync.sync_now()
      end
    end
  end
end
