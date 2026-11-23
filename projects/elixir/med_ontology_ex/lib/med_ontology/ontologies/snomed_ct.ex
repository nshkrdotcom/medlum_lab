defmodule MedOntology.SnomedCT do
  @moduledoc """
  SNOMED-CT ontology operations.

  SNOMED-CT (Systematized Nomenclature of Medicine - Clinical Terms) is the
  most comprehensive clinical terminology, covering:

    * Clinical findings and disorders
    * Procedures
    * Body structures
    * Pharmaceutical products
    * Organisms

  ## Examples

      # Lookup a concept by SCTID
      MedOntology.SnomedCT.lookup("44054006")
      #=> {:ok, %Concept{code: "44054006", display: "Type 2 diabetes mellitus"}}

      # Search by term
      MedOntology.SnomedCT.search("diabetes")
      #=> {:ok, [%SearchResult{...}, ...]}

      # Check hierarchy
      MedOntology.SnomedCT.is_a?("44054006", "73211009")
      #=> true (Type 2 DM is-a Diabetes mellitus)

      # Get relationships
      MedOntology.SnomedCT.relationships("44054006")
      #=> {:ok, [%Relationship{type: :is_a, target_code: "73211009"}, ...]}

      # Execute ECL query
      MedOntology.SnomedCT.ecl_query("<< 73211009")
      #=> {:ok, [%Concept{...}, ...]}  # All descendants of diabetes

  ## SNOMED-CT Concepts

  SNOMED-CT concepts are identified by SCTIDs (SNOMED CT Identifiers),
  which are unique numeric identifiers.

  Each concept has:
    * A Fully Specified Name (FSN) - unambiguous term with semantic tag
    * A Preferred Term (PT) - commonly used display name
    * Synonyms - alternative acceptable terms

  ## Configuration

      config :med_ontology_ex,
        snowstorm_base_url: "https://browser.ihtsdotools.org/snowstorm/snomed-ct",
        snowstorm_branch: "MAIN/2024-09-01"

  """

  @behaviour MedOntology.Ontology

  alias MedOntology.Concept
  alias MedOntology.Relationship
  alias MedOntology.SearchResult
  alias MedOntology.Cache.Server, as: Cache

  # Use configurable client for testability
  defp snowstorm_client do
    Application.get_env(:med_ontology_ex, :snowstorm_client, MedOntology.Client.Snowstorm)
  end

  # ============================================================================
  # Ontology Behaviour Implementation
  # ============================================================================

  @doc """
  Look up a SNOMED-CT concept by SCTID.

  ## Options

    * `:include_relationships` - Include related concepts (default: false)

  ## Examples

      iex> MedOntology.SnomedCT.lookup("44054006")
      {:ok, %Concept{
        code: "44054006",
        system: :snomed_ct,
        display: "Type 2 diabetes mellitus",
        fully_specified_name: "Diabetes mellitus type 2 (disorder)",
        semantic_types: ["disorder"],
        active: true
      }}

      iex> MedOntology.SnomedCT.lookup("invalid")
      {:error, :not_found}

  """
  @impl true
  def lookup(sctid, opts \\ []) do
    start_time = System.monotonic_time()

    result =
      case Cache.get(:snomed_ct, sctid) do
        {:ok, concept} ->
          emit_telemetry(:lookup, sctid, start_time, cache_hit: true)
          {:ok, concept}

        :miss ->
          case fetch_and_cache(sctid) do
            {:ok, concept} ->
              emit_telemetry(:lookup, sctid, start_time, cache_hit: false)
              {:ok, concept}

            error ->
              error
          end
      end

    if Keyword.get(opts, :include_relationships, false) do
      with {:ok, concept} <- result do
        enrich_with_relationships(concept)
      end
    else
      result
    end
  end

  @doc """
  Search for SNOMED-CT concepts by term.

  ## Options

    * `:limit` - Maximum results (default: 25)
    * `:semantic_types` - Filter by semantic types (e.g., ["disorder"])
    * `:active_only` - Only return active concepts (default: true)

  ## Examples

      iex> MedOntology.SnomedCT.search("diabetes")
      {:ok, [
        %SearchResult{
          concept: %Concept{code: "73211009", display: "Diabetes mellitus"},
          score: 1.0,
          matched_term: "Diabetes mellitus"
        },
        %SearchResult{
          concept: %Concept{code: "44054006", display: "Type 2 diabetes mellitus"},
          score: 0.85,
          matched_term: "Type 2 diabetes mellitus"
        }
      ]}

  """
  @impl true
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    semantic_types = Keyword.get(opts, :semantic_types, [])

    with {:ok, items} <- snowstorm_client().search(query, limit: limit, semantic_tags: semantic_types) do
      results =
        items
        |> Enum.map(fn item ->
          concept = parse_snowstorm_concept(item)
          score = calculate_search_score(query, concept)
          %SearchResult{concept: concept, score: score, matched_term: concept.display}
        end)
        |> Enum.sort_by(& &1.score, :desc)

      {:ok, results}
    end
  end

  @doc """
  Check if a SCTID is valid (exists and is active).

  ## Examples

      iex> MedOntology.SnomedCT.valid?("44054006")
      true

      iex> MedOntology.SnomedCT.valid?("invalid")
      false

  """
  @impl true
  def valid?(sctid) do
    case lookup(sctid) do
      {:ok, %Concept{active: true}} -> true
      _ -> false
    end
  end

  @doc """
  Get ancestor concepts (parents and their parents).

  Returns concepts in order from immediate parent to root.

  ## Options

    * `:max_depth` - Maximum levels to traverse (default: unlimited)

  ## Examples

      iex> MedOntology.SnomedCT.ancestors("44054006")
      {:ok, [
        %Concept{code: "73211009", display: "Diabetes mellitus"},
        %Concept{code: "126877002", display: "Disorder of glucose metabolism"}
      ]}

  """
  @impl true
  def ancestors(sctid, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, :infinity)
    fetch_ancestors(sctid, [], 0, max_depth)
  end

  @doc """
  Get descendant concepts (children and their children).

  ## Options

    * `:max_depth` - Maximum levels to traverse (default: 1)
    * `:limit` - Maximum results per level (default: 100)

  ## Examples

      iex> MedOntology.SnomedCT.descendants("73211009", max_depth: 1)
      {:ok, [
        %Concept{code: "44054006", display: "Type 2 diabetes mellitus"},
        %Concept{code: "46635009", display: "Type 1 diabetes mellitus"}
      ]}

  """
  @impl true
  def descendants(sctid, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, 1)
    limit = Keyword.get(opts, :limit, 100)

    fetch_descendants(sctid, [], 0, max_depth, limit)
  end

  # ============================================================================
  # SNOMED-CT Specific Functions
  # ============================================================================

  @doc """
  Check if child concept is-a parent concept (transitive).

  This function checks if the child concept is a subtype (descendant) of
  the parent concept using the is-a hierarchy.

  ## Examples

      iex> MedOntology.SnomedCT.is_a?("44054006", "73211009")
      true  # Type 2 diabetes is-a Diabetes mellitus

      iex> MedOntology.SnomedCT.is_a?("44054006", "22298006")
      false  # Type 2 diabetes is NOT a Myocardial infarction

  """
  @spec is_a?(String.t(), String.t()) :: boolean()
  def is_a?(child_sctid, parent_sctid) do
    # First check if same concept
    if child_sctid == parent_sctid do
      true
    else
      # Check cache for pre-computed relationship
      cache_key = "is_a:#{child_sctid}:#{parent_sctid}"

      case Cache.get(:snomed_ct_hierarchy, cache_key) do
        {:ok, result} ->
          result

        :miss ->
          result = compute_is_a(child_sctid, parent_sctid)
          Cache.put(:snomed_ct_hierarchy, cache_key, result)
          result
      end
    end
  end

  @doc """
  Get relationships for a concept.

  Returns all active relationships for the given concept, including
  is-a, finding-site, associated-morphology, and other SNOMED-CT relationships.

  ## Examples

      iex> MedOntology.SnomedCT.relationships("44054006")
      {:ok, [
        %Relationship{type: :is_a, source_code: "44054006", target_code: "73211009"},
        %Relationship{type: :finding_site, source_code: "44054006", target_code: "181277001"}
      ]}

  """
  @spec relationships(String.t()) :: {:ok, [Relationship.t()]} | {:error, term()}
  def relationships(sctid) do
    case snowstorm_client().get_relationships(sctid) do
      {:ok, data} ->
        rels =
          data
          |> Map.get("items", [])
          |> Enum.map(&parse_relationship/1)

        {:ok, rels}

      error ->
        error
    end
  end

  @doc """
  Execute an ECL (Expression Constraint Language) query.

  ECL is a powerful query language for SNOMED-CT that allows you to
  express complex constraints on concepts.

  ## Examples

      # All descendants of diabetes mellitus (including self)
      iex> MedOntology.SnomedCT.ecl_query("<< 73211009")
      {:ok, [%Concept{code: "44054006", ...}, ...]}

      # All descendants excluding self
      iex> MedOntology.SnomedCT.ecl_query("< 73211009")
      {:ok, [%Concept{code: "44054006", ...}, ...]}

      # Disorders with finding site in lung
      iex> MedOntology.SnomedCT.ecl_query("<< 64572001 : 363698007 = 39607008")
      {:ok, [...]}

  ## Options

    * `:limit` - Maximum results (default: 100)

  """
  @spec ecl_query(String.t(), keyword()) :: {:ok, [Concept.t()]} | {:error, term()}
  def ecl_query(ecl, opts \\ []) do
    with {:ok, items} <- snowstorm_client().ecl_query(ecl, opts) do
      concepts = Enum.map(items, &parse_snowstorm_concept/1)
      {:ok, concepts}
    end
  end

  @doc """
  Get the semantic tag (hierarchy) for a concept.

  The semantic tag indicates what type of concept this is (e.g., "disorder",
  "finding", "procedure", "body structure").

  ## Examples

      iex> MedOntology.SnomedCT.semantic_tag("44054006")
      {:ok, "disorder"}

      iex> MedOntology.SnomedCT.semantic_tag("85151006")
      {:ok, "procedure"}

  """
  @spec semantic_tag(String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def semantic_tag(sctid) do
    with {:ok, concept} <- lookup(sctid) do
      tag = List.first(concept.semantic_types)
      {:ok, tag}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp fetch_and_cache(sctid) do
    with {:ok, data} <- snowstorm_client().get_concept(sctid) do
      concept = parse_snowstorm_concept(data)
      Cache.put(:snomed_ct, sctid, concept)
      {:ok, concept}
    end
  end

  defp parse_snowstorm_concept(data) do
    fsn = get_in(data, ["fsn", "term"]) || ""
    pt = get_in(data, ["pt", "term"]) || ""

    %Concept{
      code: data["conceptId"],
      system: :snomed_ct,
      display: pt,
      fully_specified_name: fsn,
      active: data["active"],
      semantic_types: [extract_semantic_tag(fsn)],
      properties: %{
        module_id: data["moduleId"],
        definition_status: data["definitionStatus"],
        effective_time: parse_effective_time(data["effectiveTime"])
      }
    }
  end

  defp extract_semantic_tag(fsn) when is_binary(fsn) do
    case Regex.run(~r/\(([^)]+)\)$/, fsn) do
      [_, tag] -> tag
      _ -> nil
    end
  end

  defp extract_semantic_tag(_), do: nil

  defp parse_effective_time(nil), do: nil

  defp parse_effective_time(time_str) when is_binary(time_str) do
    # Snowstorm returns dates in YYYYMMDD format
    case String.length(time_str) do
      8 ->
        <<year::binary-size(4), month::binary-size(2), day::binary-size(2)>> = time_str

        case Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day)) do
          {:ok, date} -> date
          _ -> nil
        end

      _ ->
        # Try ISO8601 format
        case Date.from_iso8601(time_str) do
          {:ok, date} -> date
          _ -> nil
        end
    end
  end

  defp parse_effective_time(_), do: nil

  defp parse_relationship(data) do
    %Relationship{
      source_code: get_in(data, ["source", "conceptId"]) || data["sourceId"],
      target_code: get_in(data, ["target", "conceptId"]) || data["destinationId"],
      type: parse_relationship_type(get_in(data, ["type", "conceptId"]) || data["typeId"]),
      active: data["active"],
      group: data["relationshipGroup"] || data["groupId"]
    }
  end

  @relationship_types %{
    "116680003" => :is_a,
    "363698007" => :finding_site,
    "116676008" => :associated_morphology,
    "246075003" => :causative_agent,
    "370135005" => :pathological_process,
    "363705008" => :has_definitional_manifestation,
    "405815000" => :procedure_device
  }

  defp parse_relationship_type(type_id) do
    Map.get(@relationship_types, type_id, :other)
  end

  defp fetch_ancestors(_sctid, acc, depth, max_depth)
       when is_integer(max_depth) and depth >= max_depth do
    {:ok, Enum.reverse(acc)}
  end

  defp fetch_ancestors(sctid, acc, depth, max_depth) do
    case snowstorm_client().get_parents(sctid) do
      {:ok, parents} when parents == [] ->
        {:ok, Enum.reverse(acc)}

      {:ok, parents} ->
        concepts = Enum.map(parents, &parse_snowstorm_concept/1)
        new_acc = concepts ++ acc

        # Continue with first parent (primary hierarchy)
        case List.first(parents) do
          nil ->
            {:ok, Enum.reverse(new_acc)}

          parent ->
            fetch_ancestors(parent["conceptId"], new_acc, depth + 1, max_depth)
        end

      {:error, :not_found} ->
        {:ok, Enum.reverse(acc)}

      error ->
        error
    end
  end

  defp fetch_descendants(_sctid, acc, depth, max_depth, _limit) when depth >= max_depth do
    {:ok, Enum.reverse(acc)}
  end

  defp fetch_descendants(sctid, acc, _depth, _max_depth, limit) do
    case snowstorm_client().get_children(sctid, limit: limit) do
      {:ok, children} when children == [] ->
        {:ok, Enum.reverse(acc)}

      {:ok, children} ->
        concepts = Enum.map(children, &parse_snowstorm_concept/1)
        {:ok, concepts ++ acc}

      {:error, :not_found} ->
        {:ok, Enum.reverse(acc)}

      error ->
        error
    end
  end

  defp compute_is_a(child_sctid, parent_sctid) do
    case ancestors(child_sctid, max_depth: 10) do
      {:ok, ancestors} ->
        Enum.any?(ancestors, fn a -> a.code == parent_sctid end)

      _ ->
        false
    end
  end

  defp enrich_with_relationships(concept) do
    case relationships(concept.code) do
      {:ok, rels} ->
        {:ok, %{concept | properties: Map.put(concept.properties, :relationships, rels)}}

      _ ->
        {:ok, concept}
    end
  end

  defp calculate_search_score(query, concept) do
    query_lower = String.downcase(query)
    display_lower = String.downcase(concept.display)

    cond do
      display_lower == query_lower -> 1.0
      String.starts_with?(display_lower, query_lower) -> 0.9
      String.contains?(display_lower, query_lower) -> 0.8
      true -> String.jaro_distance(query_lower, display_lower)
    end
  end

  defp emit_telemetry(operation, code, start_time, metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:med_ontology, :snomed_ct, operation, :stop],
      %{duration: duration},
      Map.merge(%{ontology: :snomed_ct, code: code}, Map.new(metadata))
    )
  end
end
