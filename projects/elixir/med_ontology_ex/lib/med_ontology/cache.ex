defmodule MedOntology.Cache do
  @moduledoc """
  Public cache API for med_ontology_ex.

  This module provides the main interface for cache operations in the
  medical ontology library. It delegates to the underlying `Cache.Server`
  GenServer for actual operations.

  ## Architecture

  The cache system uses a multi-tier architecture:

    1. **ETS Tables** - Hot data with sub-millisecond lookups
    2. **DETS Files** - Persistence across application restarts
    3. **File Store** - Bulk data loading (future enhancement)

  ## Performance

  The cache is designed to meet strict performance requirements:

    * Single cached lookup: <10ms (typically <1ms via ETS)
    * Batch lookup (100 items): <500ms
    * Cache warmup (full dataset): <5 minutes

  ## Offline Operation

  The cache supports fully offline operation in air-gapped clinical
  environments. On startup, data is loaded from DETS files into ETS
  tables for fast access.

  ## Configuration

      config :med_ontology_ex,
        cache_dir: "/var/lib/med_ontology/cache",
        cache_warmup_on_start: true,
        sync_enabled: false,
        sync_interval_hours: 24

  ## Usage

      # Get a cached value
      case MedOntology.Cache.get(:rxnorm, "861004") do
        {:ok, concept} -> IO.inspect(concept)
        :miss -> IO.puts("Not in cache")
      end

      # Put a value in cache
      MedOntology.Cache.put(:rxnorm, "861004", %{name: "metformin"})

      # Batch operations
      entries = [{"861004", %{name: "metformin"}}, {"197361", %{name: "lisinopril"}}]
      MedOntology.Cache.put_batch(:rxnorm, entries)

      # Get cache statistics
      MedOntology.Cache.stats()

      # Clear caches
      MedOntology.Cache.clear(:rxnorm)
      MedOntology.Cache.clear_all()

  ## Supported Ontologies

  The cache supports the following ontology keys:

    * `:snomed_ct` - SNOMED-CT concepts
    * `:snomed_ct_hierarchy` - SNOMED-CT hierarchy relationships
    * `:icd10` - ICD-10 codes
    * `:rxnorm` - RxNorm concepts
    * `:rxnorm_normalize` - RxNorm normalized forms
    * `:rxnorm_class` - RxNorm drug classes
    * `:rxnorm_ingredients` - RxNorm ingredients
    * `:rxnorm_interactions` - RxNorm drug interactions
    * `:rxnorm_ndc` - RxNorm NDC mappings
    * `:loinc` - LOINC codes
    * `:loinc_panels` - LOINC panels
    * `:linker_cache` - Entity linker cache

  """

  @doc """
  Gets a value from cache.

  Returns `{:ok, value}` on cache hit, or `:miss` on cache miss.
  Expired entries are treated as cache misses.

  ## Examples

      iex> MedOntology.Cache.get(:rxnorm, "861004")
      {:ok, %{name: "metformin"}}

      iex> MedOntology.Cache.get(:snomed_ct, "nonexistent")
      :miss

  """
  @spec get(atom(), term()) :: {:ok, term()} | :miss
  defdelegate get(ontology, key), to: MedOntology.Cache.Server

  @doc """
  Gets a value even if expired (for fallback scenarios).

  This is useful when external APIs are unavailable and stale data
  is preferable to no data.

  ## Examples

      iex> MedOntology.Cache.get_stale(:rxnorm, "861004")
      {:ok, %{name: "metformin"}}

  """
  @spec get_stale(atom(), term()) :: {:ok, term()} | :miss
  defdelegate get_stale(ontology, key), to: MedOntology.Cache.Server

  @doc """
  Puts a value in cache.

  The value is stored in ETS immediately and asynchronously persisted
  to DETS for durability.

  ## Examples

      iex> MedOntology.Cache.put(:rxnorm, "861004", %{name: "metformin"})
      :ok

  """
  @spec put(atom(), term(), term()) :: :ok
  defdelegate put(ontology, key, value), to: MedOntology.Cache.Server

  @doc """
  Puts multiple values in batch.

  More efficient than individual puts for bulk loading operations.

  ## Examples

      iex> entries = [{"861004", %{name: "metformin"}}, {"197361", %{name: "lisinopril"}}]
      iex> MedOntology.Cache.put_batch(:rxnorm, entries)
      :ok

  """
  @spec put_batch(atom(), [{term(), term()}]) :: :ok
  defdelegate put_batch(ontology, entries), to: MedOntology.Cache.Server

  @doc """
  Returns cache statistics for all ontologies.

  ## Examples

      iex> MedOntology.Cache.stats()
      %{
        snomed_ct: %{exists: true, size: 50000, memory_bytes: 100000000},
        rxnorm: %{exists: true, size: 10000, memory_bytes: 20000000},
        warmup_complete: true
      }

  """
  @spec stats() :: map()
  defdelegate stats(), to: MedOntology.Cache.Server

  @doc """
  Clears all caches.

  ## Examples

      iex> MedOntology.Cache.clear_all()
      :ok

  """
  @spec clear_all() :: :ok
  defdelegate clear_all(), to: MedOntology.Cache.Server

  @doc """
  Clears cache for a specific ontology.

  ## Examples

      iex> MedOntology.Cache.clear(:rxnorm)
      :ok

  """
  @spec clear(atom()) :: :ok
  defdelegate clear(ontology), to: MedOntology.Cache.Server

  @doc """
  Triggers a warmup from DETS.

  This loads all DETS entries into ETS tables. Normally this happens
  automatically on application startup, but can be triggered manually
  if needed.

  ## Examples

      iex> MedOntology.Cache.warmup()
      :ok

  """
  @spec warmup() :: :ok
  defdelegate warmup(), to: MedOntology.Cache.Server

  @doc """
  Returns the list of all cache tables.

  ## Examples

      iex> MedOntology.Cache.tables()
      [:snomed_ct_cache, :icd10_cache, :rxnorm_cache, :loinc_cache, ...]

  """
  @spec tables() :: [atom()]
  defdelegate tables(), to: MedOntology.Cache.Server
end
