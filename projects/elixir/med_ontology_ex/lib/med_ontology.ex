defmodule MedOntology do
  @moduledoc """
  Unified medical ontology lookup service.

  Provides access to SNOMED-CT, ICD-10, RxNorm, and LOINC ontologies
  through a consistent API.

  ## Quick Start

      # Lookup by code
      MedOntology.lookup(:snomed_ct, "44054006")
      MedOntology.lookup(:icd10, "E11.9")
      MedOntology.lookup(:rxnorm, "861004")
      MedOntology.lookup(:loinc, "2345-7")

      # Search by text
      MedOntology.search(:snomed_ct, "type 2 diabetes")

      # Cross-ontology mapping
      MedOntology.map(:snomed_ct, "44054006", :icd10)

  ## Supported Ontologies

    * `:snomed_ct` - SNOMED Clinical Terms
    * `:icd10` - International Classification of Diseases, 10th Revision
    * `:rxnorm` - RxNorm medication terminology
    * `:loinc` - Logical Observation Identifiers Names and Codes

  ## Architecture

  The library is organized in layers:

    * **Public API** (`MedOntology`) - Unified facade for all ontologies
    * **Ontology Modules** - Dedicated modules per ontology
    * **Cache Layer** - ETS/DETS caching for offline operation
    * **Client Layer** - HTTP clients for external APIs

  ## Configuration

  Configure the library in your `config.exs`:

      config :med_ontology_ex,
        umls_api_key: System.get_env("UMLS_API_KEY"),
        cache_dir: "/var/lib/med_ontology/cache",
        cache_warmup_on_start: true,
        sync_enabled: false

  See `MedOntology.Config` for all configuration options.

  """

  alias MedOntology.{Concept, Mapping, SearchResult}

  @type ontology :: :snomed_ct | :icd10 | :rxnorm | :loinc

  # ============================================================================
  # Lookup Functions
  # ============================================================================

  @doc """
  Look up a concept by its code.

  ## Examples

      iex> MedOntology.lookup(:snomed_ct, "44054006")
      {:ok, %MedOntology.Concept{code: "44054006", display: "Type 2 diabetes mellitus"}}

      iex> MedOntology.lookup(:icd10, "INVALID")
      {:error, :not_found}

  ## Options

    * `:include_relationships` - Include related concepts (default: false)
    * `:include_mappings` - Include cross-ontology mappings (default: false)

  """
  @spec lookup(ontology(), String.t(), keyword()) ::
          {:ok, Concept.t()} | {:error, :not_found | :invalid_ontology | term()}
  def lookup(ontology, code, opts \\ [])

  def lookup(:rxnorm, code, opts), do: MedOntology.RxNorm.lookup(code, opts)
  def lookup(:snomed_ct, code, opts), do: MedOntology.SnomedCT.lookup(code, opts)
  def lookup(:icd10, code, opts), do: MedOntology.ICD10.lookup(code, opts)
  def lookup(:loinc, code, opts), do: MedOntology.LOINC.lookup(code, opts)
  def lookup(_ontology, _code, _opts), do: {:error, :invalid_ontology}

  @doc """
  Look up multiple concepts by their codes.

  Returns a map of code => concept, with nil for not found codes.

  ## Examples

      iex> MedOntology.lookup_batch(:rxnorm, ["861004", "197361", "invalid"])
      {:ok, %{
        "861004" => %Concept{code: "861004", display: "metformin 500 MG"},
        "197361" => %Concept{code: "197361", display: "lisinopril 10 MG"},
        "invalid" => nil
      }}

  """
  @spec lookup_batch(ontology(), [String.t()], keyword()) ::
          {:ok, %{String.t() => Concept.t() | nil}} | {:error, term()}
  def lookup_batch(ontology, codes, opts \\ []) do
    results =
      codes
      |> Enum.map(fn code ->
        result = lookup(ontology, code, opts)
        {code, elem(result, 1) |> then(fn x -> if is_struct(x, Concept), do: x, else: nil end)}
      end)
      |> Map.new()

    {:ok, results}
  end

  # ============================================================================
  # Search Functions
  # ============================================================================

  @doc """
  Search for concepts by text.

  ## Examples

      iex> MedOntology.search(:snomed_ct, "type 2 diabetes")
      {:ok, [
        %SearchResult{
          concept: %Concept{code: "44054006", display: "Type 2 diabetes mellitus"},
          score: 0.95,
          matched_term: "Type 2 diabetes mellitus"
        }
      ]}

  ## Options

    * `:limit` - Maximum number of results (default: 25)
    * `:semantic_types` - Filter by semantic types (e.g., ["disorder"])
    * `:active_only` - Only return active concepts (default: true)
    * `:min_score` - Minimum relevance score (default: 0.5)

  """
  @spec search(ontology(), String.t(), keyword()) ::
          {:ok, [SearchResult.t()]} | {:error, term()}
  def search(ontology, query, opts \\ [])

  def search(:rxnorm, query, opts), do: MedOntology.RxNorm.search(query, opts)
  def search(:snomed_ct, query, opts), do: MedOntology.SnomedCT.search(query, opts)
  def search(:icd10, query, opts), do: MedOntology.ICD10.search(query, opts)
  def search(:loinc, query, opts), do: MedOntology.LOINC.search(query, opts)
  def search(_ontology, _query, _opts), do: {:error, :invalid_ontology}

  # ============================================================================
  # Validation Functions
  # ============================================================================

  @doc """
  Check if a code is valid for the given ontology.

  Validates both format and existence (when cache is available).

  ## Examples

      iex> MedOntology.valid?(:icd10, "E11.9")
      true

      iex> MedOntology.valid?(:icd10, "ZZZ.99")
      false

  """
  @spec valid?(ontology(), String.t()) :: boolean()
  def valid?(ontology, code)

  def valid?(:rxnorm, code), do: MedOntology.RxNorm.valid?(code)
  def valid?(:snomed_ct, code), do: MedOntology.SnomedCT.valid?(code)
  def valid?(:icd10, code), do: MedOntology.ICD10.valid?(code)
  def valid?(:loinc, code), do: MedOntology.LOINC.valid?(code)
  def valid?(_ontology, _code), do: false

  # ============================================================================
  # Hierarchy Functions
  # ============================================================================

  @doc """
  Get the ancestors (parents) of a concept.

  Returns concepts in order from immediate parent to root.

  ## Examples

      iex> MedOntology.ancestors(:snomed_ct, "44054006")
      {:ok, [
        %Concept{code: "73211009", display: "Diabetes mellitus"},
        %Concept{code: "126877002", display: "Disorder of glucose metabolism"}
      ]}

  ## Options

    * `:max_depth` - Maximum levels to traverse (default: unlimited)

  """
  @spec ancestors(ontology(), String.t(), keyword()) ::
          {:ok, [Concept.t()]} | {:error, term()}
  def ancestors(ontology, code, opts \\ [])

  def ancestors(:snomed_ct, code, opts), do: MedOntology.SnomedCT.ancestors(code, opts)
  def ancestors(:icd10, code, opts), do: MedOntology.ICD10.ancestors(code, opts)
  def ancestors(:rxnorm, code, opts), do: MedOntology.RxNorm.ancestors(code, opts)
  def ancestors(:loinc, code, opts), do: MedOntology.LOINC.ancestors(code, opts)
  def ancestors(_ontology, _code, _opts), do: {:error, :invalid_ontology}

  @doc """
  Get the descendants (children) of a concept.

  ## Examples

      iex> MedOntology.descendants(:snomed_ct, "73211009", max_depth: 1)
      {:ok, [
        %Concept{code: "44054006", display: "Type 2 diabetes mellitus"},
        %Concept{code: "46635009", display: "Type 1 diabetes mellitus"}
      ]}

  ## Options

    * `:max_depth` - Maximum levels to traverse (default: 1)
    * `:limit` - Maximum number of results (default: 100)

  """
  @spec descendants(ontology(), String.t(), keyword()) ::
          {:ok, [Concept.t()]} | {:error, term()}
  def descendants(ontology, code, opts \\ [])

  def descendants(:snomed_ct, code, opts), do: MedOntology.SnomedCT.descendants(code, opts)
  def descendants(:icd10, code, opts), do: MedOntology.ICD10.descendants(code, opts)
  def descendants(:rxnorm, code, opts), do: MedOntology.RxNorm.descendants(code, opts)
  def descendants(:loinc, code, opts), do: MedOntology.LOINC.descendants(code, opts)
  def descendants(_ontology, _code, _opts), do: {:error, :invalid_ontology}

  @doc """
  Check if child concept is-a (subsumes to) parent concept.

  Uses transitive closure - returns true if parent is anywhere
  in the ancestor chain.

  ## Examples

      iex> MedOntology.is_a?(:snomed_ct, "44054006", "73211009")
      true  # Type 2 diabetes is-a Diabetes mellitus

  """
  @spec is_a?(ontology(), String.t(), String.t()) :: boolean()
  def is_a?(ontology, child_code, parent_code) do
    # TODO: Implement when ancestors/3 is fully implemented
    # For now, delegate to ontology-specific implementation or return false
    case ontology do
      :snomed_ct -> MedOntology.SnomedCT.is_a?(child_code, parent_code)
      _ -> false
    end
  end

  # ============================================================================
  # Mapping Functions
  # ============================================================================

  @doc """
  Map a concept from one ontology to another.

  ## Examples

      iex> MedOntology.map(:snomed_ct, "44054006", :icd10)
      {:ok, [
        %Mapping{
          source_system: :snomed_ct,
          source_code: "44054006",
          target_system: :icd10,
          target_code: "E11.9",
          equivalence: :equivalent
        }
      ]}

  """
  @spec map(ontology(), String.t(), ontology()) ::
          {:ok, [Mapping.t()]} | {:error, :unsupported_mapping | term()}
  def map(from_ontology, code, to_ontology) do
    MedOntology.Mapper.map(from_ontology, code, to_ontology)
  end

  @doc """
  Get all mappings for a concept across all ontologies.

  ## Examples

      iex> MedOntology.all_mappings(:snomed_ct, "44054006")
      {:ok, %{
        icd10: [%Mapping{target_code: "E11.9", ...}]
      }}

  """
  @spec all_mappings(ontology(), String.t()) ::
          {:ok, %{atom() => [Mapping.t()]}} | {:error, term()}
  def all_mappings(ontology, code) do
    MedOntology.Mapper.all_mappings(ontology, code)
  end

  # ============================================================================
  # Cache Management Functions
  # ============================================================================

  @doc """
  Warm up the cache for specified ontologies.

  Loads cached data from disk and optionally syncs with APIs.

  ## Examples

      iex> MedOntology.warmup([:snomed_ct, :rxnorm])
      :ok

  ## Options

    * `:sync` - Also fetch latest from API (default: false)
    * `:progress_callback` - Function called with progress updates

  """
  @spec warmup([ontology()], keyword()) :: :ok | {:error, term()}
  def warmup(ontologies, opts \\ []) do
    MedOntology.Cache.Warmer.warmup(ontologies, opts)
  end

  @doc """
  Get cache statistics.

  ## Examples

      iex> MedOntology.cache_stats()
      %{
        snomed_ct: %{count: 450000, memory_bytes: 1200000000},
        rxnorm: %{count: 150000, memory_bytes: 200000000},
        icd10: %{count: 72000, memory_bytes: 50000000},
        loinc: %{count: 100000, memory_bytes: 100000000}
      }

  """
  @spec cache_stats() :: map()
  def cache_stats do
    MedOntology.Cache.Server.stats()
  end

  @doc """
  Clear the cache for specified ontologies.

  ## Examples

      iex> MedOntology.clear_cache([:rxnorm])
      :ok

  """
  @spec clear_cache([ontology()]) :: :ok
  def clear_cache(ontologies) do
    MedOntology.Cache.Server.clear(ontologies)
  end
end
