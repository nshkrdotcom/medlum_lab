defmodule MedOntology.RxNorm do
  @moduledoc """
  RxNorm ontology operations for medication terminology.

  RxNorm is the standardized nomenclature for clinical drugs maintained
  by the National Library of Medicine (NLM). It provides normalized names
  for medications, drug class information, and NDC mappings.

  ## Examples

      # Lookup by RxCUI
      MedOntology.RxNorm.lookup("861004")
      # => {:ok, %Concept{code: "861004", display: "metformin hydrochloride 500 MG Oral Tablet"}}

      # Normalize drug string
      MedOntology.RxNorm.normalize("metformin 500mg tablet")
      # => {:ok, %Concept{code: "861004", ...}}

      # Search for medications
      MedOntology.RxNorm.search("metformin")
      # => {:ok, [%SearchResult{...}]}

      # Get ingredients
      MedOntology.RxNorm.ingredients("861004")
      # => {:ok, [%Concept{code: "6809", display: "Metformin"}]}

      # Get drug class
      MedOntology.RxNorm.drug_class("861004")
      # => {:ok, %{atc: ["A10BA02"], ...}}

      # Get NDC codes
      MedOntology.RxNorm.ndc_codes("861004")
      # => {:ok, ["00378-0226-01", ...]}

      # Check drug interactions
      MedOntology.RxNorm.interactions("861004", "197361")
      # => {:ok, [%{severity: "moderate", description: "..."}]}

  ## RxNorm Term Types (TTY)

  RxNorm categorizes drug concepts by term type:

    * `IN` - Ingredient (e.g., "metformin")
    * `PIN` - Precise Ingredient (e.g., "metformin hydrochloride")
    * `SCDC` - Semantic Clinical Drug Component (e.g., "metformin 500 MG")
    * `SCD` - Semantic Clinical Drug (e.g., "metformin 500 MG Oral Tablet")
    * `SBD` - Semantic Branded Drug (e.g., "Glucophage 500 MG Oral Tablet")
    * `BN` - Brand Name (e.g., "Glucophage")
    * `GPCK` - Generic Pack
    * `BPCK` - Branded Pack

  For CVL verification, SCD (Semantic Clinical Drug) and SBD (Semantic Branded Drug)
  are the most commonly used term types as they represent complete drug products.

  ## Configuration

      config :med_ontology_ex,
        rxnav_client: MedOntology.Client.RxNav  # For testing with mocks

  """

  @behaviour MedOntology.Ontology

  alias MedOntology.Cache.Server, as: Cache
  alias MedOntology.Concept
  alias MedOntology.SearchResult

  # Use configurable client for testability
  defp rxnav_client do
    Application.get_env(:med_ontology_ex, :rxnav_client, MedOntology.Client.RxNav)
  end

  # ============================================================================
  # Ontology Behaviour Implementation
  # ============================================================================

  @doc """
  Look up a medication by RxCUI.

  ## Options

    * `:include_relationships` - Include related concepts (default: false)
    * `:include_mappings` - Include cross-ontology mappings (default: false)

  ## Examples

      iex> MedOntology.RxNorm.lookup("861004")
      {:ok, %Concept{
        code: "861004",
        system: :rxnorm,
        display: "metformin hydrochloride 500 MG Oral Tablet",
        semantic_types: ["SCD"],
        active: true
      }}

      iex> MedOntology.RxNorm.lookup("invalid")
      {:error, :not_found}

  """
  @impl true
  def lookup(rxcui, opts \\ []) do
    start_time = System.monotonic_time()

    result =
      case Cache.get(:rxnorm, rxcui) do
        {:ok, concept} ->
          emit_telemetry(:lookup, rxcui, start_time, cache_hit: true)
          {:ok, concept}

        :miss ->
          case fetch_and_cache(rxcui) do
            {:ok, concept} ->
              emit_telemetry(:lookup, rxcui, start_time, cache_hit: false)
              {:ok, concept}

            error ->
              error
          end
      end

    if Keyword.get(opts, :include_relationships, false) do
      with {:ok, concept} <- result do
        enrich_with_ingredients(concept)
      end
    else
      result
    end
  end

  @doc """
  Search for medications by name.

  Uses fuzzy matching to find concepts matching the query.
  Results are sorted by relevance score.

  ## Options

    * `:limit` - Maximum results (default: 25)
    * `:active_only` - Only return active concepts (default: true)

  ## Examples

      iex> MedOntology.RxNorm.search("metformin")
      {:ok, [
        %SearchResult{
          concept: %Concept{code: "861004", display: "metformin 500 MG Oral Tablet"},
          score: 0.95,
          matched_term: "metformin 500 MG Oral Tablet"
        }
      ]}

  """
  @impl true
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)

    with {:ok, items} <- rxnav_client().search(query, opts) do
      results =
        items
        |> Enum.take(limit)
        |> Enum.map(fn item ->
          concept = parse_concept_properties(item)
          score = calculate_search_score(query, concept.display)
          %SearchResult{concept: concept, score: score, matched_term: concept.display}
        end)
        |> Enum.sort_by(& &1.score, :desc)

      {:ok, results}
    end
  end

  @doc """
  Check if an RxCUI is valid.

  Validates both the format (numeric) and existence of the code.

  ## Examples

      iex> MedOntology.RxNorm.valid?("861004")
      true

      iex> MedOntology.RxNorm.valid?("invalid")
      false

  """
  @impl true
  def valid?(rxcui) do
    # First check format (must be numeric)
    case Integer.parse(rxcui) do
      {_num, ""} ->
        # Then check existence
        case lookup(rxcui) do
          {:ok, _concept} -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  @doc """
  Get ancestor concepts (ingredients, drug components).

  For RxNorm, ancestors are typically the ingredient concepts
  that make up a drug product.

  ## Options

    * `:max_depth` - Maximum levels to traverse (default: unlimited)

  ## Examples

      iex> MedOntology.RxNorm.ancestors("861004")
      {:ok, [%Concept{code: "6809", display: "Metformin"}]}

  """
  @impl true
  def ancestors(rxcui, _opts \\ []) do
    ingredients(rxcui)
  end

  @doc """
  Get descendant concepts (branded drugs, packs).

  Not typically used for RxNorm as the hierarchy is ingredient-based
  rather than parent-child based.

  ## Options

    * `:max_depth` - Maximum levels to traverse (default: 1)
    * `:limit` - Maximum number of results (default: 100)

  ## Examples

      iex> MedOntology.RxNorm.descendants("6809")
      {:ok, []}  # Ingredients don't have descendants in traditional sense

  """
  @impl true
  def descendants(_rxcui, _opts \\ []) do
    # RxNorm hierarchy is ingredient-based, not parent-child
    # Descendants would be drug products containing an ingredient,
    # but this is better handled by search
    {:ok, []}
  end

  # ============================================================================
  # RxNorm-Specific Functions
  # ============================================================================

  @doc """
  Normalize a drug string to an RxNorm concept.

  This is the primary function for matching free-text medication mentions
  to standardized RxNorm concepts. Uses approximate matching to handle
  variations in drug names, strengths, and dose forms.

  ## Examples

      iex> MedOntology.RxNorm.normalize("metformin 500mg tablet")
      {:ok, %Concept{code: "861004", display: "metformin hydrochloride 500 MG Oral Tablet"}}

      iex> MedOntology.RxNorm.normalize("glucophage 500")
      {:ok, %Concept{code: "861007", display: "Glucophage 500 MG Oral Tablet"}}

      iex> MedOntology.RxNorm.normalize("invalid drug xyz")
      {:error, :not_found}

  """
  @spec normalize(String.t()) :: {:ok, Concept.t()} | {:error, term()}
  def normalize(drug_string) do
    # First check cache for the normalized string
    cache_key = "normalize:#{String.downcase(drug_string)}"

    case Cache.get(:rxnorm, cache_key) do
      {:ok, concept} ->
        {:ok, concept}

      :miss ->
        with {:ok, rxcui} <- rxnav_client().get_rxcui(drug_string),
             {:ok, concept} <- lookup(rxcui) do
          Cache.put(:rxnorm, cache_key, concept)
          {:ok, concept}
        end
    end
  end

  @doc """
  Get drug class information for a medication.

  Returns classifications from multiple systems:

    * `atc` - Anatomical Therapeutic Chemical Classification
    * `va_class` - Veterans Administration Drug Classification
    * `ndf_rt` - National Drug File Reference Terminology

  ## Examples

      iex> MedOntology.RxNorm.drug_class("861004")
      {:ok, %{
        atc: ["A10BA02"],
        va_class: ["HS502"],
        ndf_rt: ["N0000175503"]
      }}

  """
  @spec drug_class(String.t()) :: {:ok, map()} | {:error, term()}
  def drug_class(rxcui) do
    cache_key = "class:#{rxcui}"

    case Cache.get(:rxnorm, cache_key) do
      {:ok, classes} ->
        {:ok, classes}

      :miss ->
        fetch_and_cache_classes(rxcui, cache_key)
    end
  end

  @doc """
  Get ingredients for a drug product.

  Returns the active ingredients (IN) and precise ingredients (PIN)
  for the given RxNorm concept.

  ## Examples

      iex> MedOntology.RxNorm.ingredients("861004")
      {:ok, [%Concept{code: "6809", display: "Metformin", semantic_types: ["IN"]}]}

      iex> MedOntology.RxNorm.ingredients("197361")
      {:ok, [%Concept{code: "29046", display: "Lisinopril", semantic_types: ["IN"]}]}

  """
  @spec ingredients(String.t()) :: {:ok, [Concept.t()]} | {:error, term()}
  def ingredients(rxcui) do
    cache_key = "ingredients:#{rxcui}"

    case Cache.get(:rxnorm, cache_key) do
      {:ok, ingredient_concepts} ->
        {:ok, ingredient_concepts}

      :miss ->
        with {:ok, items} <- rxnav_client().get_ingredients(rxcui) do
          concepts = Enum.map(items, &parse_concept_properties/1)
          Cache.put(:rxnorm, cache_key, concepts)
          {:ok, concepts}
        end
    end
  end

  @doc """
  Get drug-drug interactions.

  Checks for known interactions between two medications using the
  RxNorm Interaction API.

  ## Examples

      iex> MedOntology.RxNorm.interactions("861004", "197361")
      {:ok, [
        %{severity: "moderate", description: "May increase risk of..."}
      ]}

      iex> MedOntology.RxNorm.interactions("861004", "861004")
      {:ok, []}  # No self-interactions

  """
  @spec interactions(String.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def interactions(rxcui1, rxcui2) do
    # Normalize key order for consistent caching
    {first, second} = if rxcui1 <= rxcui2, do: {rxcui1, rxcui2}, else: {rxcui2, rxcui1}
    cache_key = "interactions:#{first}:#{second}"

    case Cache.get(:rxnorm, cache_key) do
      {:ok, interaction_list} ->
        {:ok, interaction_list}

      :miss ->
        with {:ok, data} <- rxnav_client().get_interactions(rxcui1, rxcui2) do
          interaction_list = parse_interactions(data)
          Cache.put(:rxnorm, cache_key, interaction_list)
          {:ok, interaction_list}
        end
    end
  end

  @doc """
  Get NDC (National Drug Code) codes for an RxNorm concept.

  NDC codes are used for identifying drug products in the US healthcare system.

  ## Examples

      iex> MedOntology.RxNorm.ndc_codes("861004")
      {:ok, ["00378-0226-01", "00591-2468-01", ...]}

  """
  @spec ndc_codes(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def ndc_codes(rxcui) do
    cache_key = "ndc:#{rxcui}"

    case Cache.get(:rxnorm, cache_key) do
      {:ok, ndcs} ->
        {:ok, ndcs}

      :miss ->
        with {:ok, ndcs} <- rxnav_client().get_ndc(rxcui) do
          Cache.put(:rxnorm, cache_key, ndcs)
          {:ok, ndcs}
        end
    end
  end

  @doc """
  Gets the dose form for a drug product.

  Extracts the dose form from the concept display name.

  ## Examples

      iex> MedOntology.RxNorm.dose_form("861004")
      {:ok, "Oral Tablet"}

  """
  @spec dose_form(String.t()) :: {:ok, String.t()} | {:error, term()}
  def dose_form(rxcui) do
    with {:ok, concept} <- lookup(rxcui) do
      # Extract dose form from the display name
      # Typically at the end: "metformin 500 MG Oral Tablet"
      extracted = extract_dose_form(concept.display)
      {:ok, extracted}
    end
  end

  @doc """
  Gets strength information for a drug product.

  Extracts strength (value and unit) from the concept display name.

  ## Examples

      iex> MedOntology.RxNorm.strength("861004")
      {:ok, %{value: "500", unit: "MG"}}

  """
  @spec strength(String.t()) :: {:ok, map()} | {:error, term()}
  def strength(rxcui) do
    with {:ok, concept} <- lookup(rxcui) do
      extracted = extract_strength(concept.display)
      {:ok, extracted}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp fetch_and_cache(rxcui) do
    with {:ok, data} <- rxnav_client().get_concept(rxcui) do
      concept = parse_all_properties(data)
      Cache.put(:rxnorm, rxcui, concept)
      {:ok, concept}
    end
  end

  defp parse_all_properties(data) do
    props = get_in(data, ["propConceptGroup", "propConcept"]) || []

    %Concept{
      code: find_prop(props, "rxcui") || find_prop(props, "RXCUI"),
      system: :rxnorm,
      display: find_prop(props, "RxNorm Name") || find_prop(props, "name"),
      synonyms: find_all_props(props, "RxNorm Synonym") ++ find_all_props(props, "synonym"),
      active: true,
      semantic_types: [find_prop(props, "TTY") || find_prop(props, "tty")],
      properties: %{
        tty: find_prop(props, "TTY") || find_prop(props, "tty"),
        rxaui: find_prop(props, "RXAUI") || find_prop(props, "rxaui"),
        suppress: find_prop(props, "SUPPRESS") || find_prop(props, "suppress"),
        language: find_prop(props, "LANGUAGE") || find_prop(props, "language")
      }
    }
  end

  defp parse_concept_properties(item) do
    %Concept{
      code: item["rxcui"],
      system: :rxnorm,
      display: item["name"],
      synonyms: List.wrap(item["synonym"]),
      active: true,
      semantic_types: [item["tty"]],
      properties: %{
        tty: item["tty"]
      }
    }
  end

  defp find_prop(props, name) do
    Enum.find_value(props, fn p ->
      if p["propName"] == name, do: p["propValue"]
    end)
  end

  defp find_all_props(props, name) do
    props
    |> Enum.filter(fn p -> p["propName"] == name end)
    |> Enum.map(fn p -> p["propValue"] end)
  end

  defp fetch_and_cache_classes(rxcui, cache_key) do
    # Fetch from multiple classification systems
    atc = fetch_class_codes(rxcui, "ATC")
    va = fetch_class_codes(rxcui, "VA")
    ndfrt = fetch_class_codes(rxcui, "NDFRT")

    classes = %{
      atc: atc,
      va_class: va,
      ndf_rt: ndfrt
    }

    Cache.put(:rxnorm, cache_key, classes)
    {:ok, classes}
  end

  defp fetch_class_codes(rxcui, class_type) do
    case rxnav_client().get_drug_class(rxcui, class_type) do
      {:ok, classes} ->
        classes
        |> Enum.map(fn c ->
          get_in(c, ["rxclassMinConceptItem", "classId"])
        end)
        |> Enum.filter(& &1)

      _ ->
        []
    end
  end

  defp parse_interactions(data) do
    data
    |> Enum.flat_map(fn group ->
      get_in(group, ["fullInteractionType"]) || []
    end)
    |> Enum.flat_map(fn type ->
      interaction_pairs = get_in(type, ["interactionPair"]) || []

      Enum.map(interaction_pairs, fn pair ->
        %{
          severity: get_in(pair, ["severity"]),
          description: get_in(pair, ["description"])
        }
      end)
    end)
  end

  defp calculate_search_score(query, display) do
    query_lower = String.downcase(query)
    display_lower = String.downcase(display || "")

    cond do
      display_lower == query_lower -> 1.0
      String.starts_with?(display_lower, query_lower) -> 0.9
      String.contains?(display_lower, query_lower) -> 0.8
      true -> String.jaro_distance(query_lower, display_lower)
    end
  end

  defp enrich_with_ingredients(concept) do
    case ingredients(concept.code) do
      {:ok, ingredient_concepts} ->
        {:ok, %{concept | properties: Map.put(concept.properties, :ingredients, ingredient_concepts)}}

      _ ->
        {:ok, concept}
    end
  end

  # Common dose form patterns in RxNorm
  @dose_forms [
    "Oral Tablet",
    "Oral Capsule",
    "Injectable Solution",
    "Oral Solution",
    "Oral Suspension",
    "Topical Cream",
    "Topical Ointment",
    "Nasal Spray",
    "Inhalation Aerosol",
    "Ophthalmic Solution",
    "Rectal Suppository",
    "Transdermal Patch",
    "Sublingual Tablet",
    "Chewable Tablet",
    "Extended Release Oral Tablet",
    "Delayed Release Oral Capsule"
  ]

  defp extract_dose_form(display) when is_binary(display) do
    Enum.find(@dose_forms, "Unknown", fn form ->
      String.contains?(String.downcase(display), String.downcase(form))
    end)
  end

  defp extract_dose_form(_), do: "Unknown"

  defp extract_strength(display) when is_binary(display) do
    # Pattern: "drug name 500 MG dose form" or "drug name 500 MG/5 ML solution"
    case Regex.run(~r/(\d+(?:\.\d+)?)\s*(MG|MCG|G|ML|%|UNIT|IU)/i, display) do
      [_, value, unit] ->
        %{value: value, unit: String.upcase(unit)}

      _ ->
        %{value: nil, unit: nil}
    end
  end

  defp extract_strength(_), do: %{value: nil, unit: nil}

  defp emit_telemetry(operation, code, start_time, metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:med_ontology, :rxnorm, operation, :stop],
      %{duration: duration},
      Map.merge(%{ontology: :rxnorm, code: code}, Map.new(metadata))
    )
  end
end
