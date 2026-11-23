defmodule MedOntology.ICD10 do
  @moduledoc """
  ICD-10 ontology operations.

  ICD-10 (International Classification of Diseases, 10th Revision) is the
  standard for diagnosis coding in healthcare. This module supports ICD-10-CM
  (US Clinical Modification) as the primary source.

  ## ICD-10-CM Structure

  ICD-10-CM codes are organized hierarchically:

      Chapter (e.g., "Endocrine, nutritional and metabolic diseases")
        +-- Block (e.g., E10-E14 "Diabetes mellitus")
             +-- Category (e.g., E11 "Type 2 diabetes mellitus")
                  +-- Subcategory (e.g., E11.9 "Type 2 DM without complications")

  ## Code Format

  ICD-10-CM codes consist of:
  - A single letter (A-Z, excluding U)
  - Two digits
  - Optionally, a decimal point followed by 1-4 alphanumeric characters

  Examples: `I10`, `E11.9`, `M54.50`, `S72.001A`

  ## Billability

  Not all ICD-10 codes are billable. Category codes (3 characters) typically
  are not billable - more specific subcategory codes are required for billing.

  ## Examples

      # Lookup a code
      MedOntology.ICD10.lookup("E11.9")
      #=> {:ok, %Concept{code: "E11.9", display: "Type 2 diabetes mellitus without complications"}}

      # Check if code is valid
      MedOntology.ICD10.valid?("E11.9")
      #=> true

      # Check if code is billable
      MedOntology.ICD10.billable?("E11.9")
      #=> true

      # Get hierarchy information
      MedOntology.ICD10.hierarchy("E11.9")
      #=> {:ok, %{chapter: "IV", block: "E10-E14", ...}}

      # Search by description
      MedOntology.ICD10.search("diabetes")
      #=> {:ok, [%SearchResult{concept: %Concept{code: "E11.9", ...}, score: 0.85}, ...]}

  ## Data Sources

  - **Primary**: CMS ICD-10-CM files (local database)
  - **Secondary**: WHO ICD API (optional fallback for international lookups)

  """

  @behaviour MedOntology.Ontology

  alias MedOntology.Cache.Server, as: Cache
  alias MedOntology.Client.WHO
  alias MedOntology.{Concept, SearchResult}
  alias MedOntology.ICD10.{Chapters, Codes}

  # ICD-10-CM code format: Letter followed by 2 digits, optionally a decimal and 1-4 more characters
  # The characters after the decimal can be digits or letters (for 7th character extensions)
  @code_pattern ~r/^[A-Z][0-9]{2}(\.[0-9A-Z]{1,4})?$/i

  # ============================================================================
  # Ontology Behaviour Callbacks
  # ============================================================================

  @doc """
  Look up an ICD-10 code.

  Returns a Concept struct with the code's description, billability status,
  and other metadata.

  ## Options

    * `:include_relationships` - Include related concepts (default: false)
    * `:include_mappings` - Include cross-ontology mappings (default: false)

  ## Examples

      iex> MedOntology.ICD10.lookup("E11.9")
      {:ok, %Concept{code: "E11.9", display: "Type 2 diabetes mellitus without complications"}}

      iex> MedOntology.ICD10.lookup("ZZZ.99")
      {:error, :not_found}

  """
  @impl true
  @spec lookup(String.t(), keyword()) :: {:ok, Concept.t()} | {:error, :not_found | term()}
  def lookup(code, opts \\ []) do
    normalized_code = normalize_code(code)

    # Check cache first
    case Cache.get(:icd10, normalized_code) do
      {:ok, concept} ->
        {:ok, concept}

      :miss ->
        # Try local code database first
        case Codes.get(normalized_code) do
          {:ok, data} ->
            concept = build_concept(normalized_code, data)
            Cache.put(:icd10, normalized_code, concept)
            {:ok, maybe_include_extra(concept, opts)}

          :not_found ->
            # Fallback to WHO API if configured
            fetch_from_who(normalized_code, opts)
        end
    end
  end

  @doc """
  Search for ICD-10 codes by description.

  Performs a case-insensitive search on code descriptions.

  ## Options

    * `:limit` - Maximum number of results (default: 25)
    * `:min_score` - Minimum relevance score (default: 0.5)
    * `:active_only` - Only return active concepts (default: true)

  ## Examples

      iex> MedOntology.ICD10.search("diabetes")
      {:ok, [%SearchResult{concept: %Concept{code: "E11.9", ...}, score: 0.85}, ...]}

  """
  @impl true
  @spec search(String.t(), keyword()) :: {:ok, [SearchResult.t()]} | {:error, term()}
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    min_score = Keyword.get(opts, :min_score, 0.5)

    # Search local code database
    results =
      Codes.search(query, limit: limit * 2)
      |> Enum.map(fn {code, data} ->
        concept = build_concept(code, data)
        score = calculate_search_score(query, concept.display)
        %SearchResult{concept: concept, score: score, matched_term: concept.display}
      end)
      |> Enum.filter(&(&1.score >= min_score))
      |> Enum.sort_by(& &1.score, :desc)
      |> Enum.take(limit)

    {:ok, results}
  end

  @doc """
  Check if an ICD-10 code is valid (format and existence).

  Validates both the code format and checks if it exists in the database.

  ## Examples

      iex> MedOntology.ICD10.valid?("E11.9")
      true

      iex> MedOntology.ICD10.valid?("INVALID")
      false

  """
  @impl true
  @spec valid?(String.t()) :: boolean()
  def valid?(code) do
    valid_format?(code) and exists?(code)
  end

  @doc """
  Get ancestor codes (category -> block -> chapter).

  Returns parent codes in order from immediate parent to root.

  ## Options

    * `:max_depth` - Maximum levels to traverse (default: unlimited)

  ## Examples

      iex> MedOntology.ICD10.ancestors("E11.9")
      {:ok, [%Concept{code: "E11", display: "Type 2 diabetes mellitus"}]}

  """
  @impl true
  @spec ancestors(String.t(), keyword()) :: {:ok, [Concept.t()]} | {:error, term()}
  def ancestors(code, opts \\ []) do
    normalized = normalize_code(code)
    max_depth = Keyword.get(opts, :max_depth)

    with {:ok, hierarchy} <- hierarchy(normalized) do
      ancestors = build_ancestor_list(hierarchy, max_depth)
      {:ok, ancestors}
    end
  end

  @doc """
  Get descendant codes (subcategories under a category).

  ## Options

    * `:max_depth` - Maximum levels to traverse (default: 1)
    * `:limit` - Maximum number of results (default: 100)

  ## Examples

      iex> MedOntology.ICD10.descendants("E11")
      {:ok, [%Concept{code: "E11.9", ...}, %Concept{code: "E11.65", ...}, ...]}

  """
  @impl true
  @spec descendants(String.t(), keyword()) :: {:ok, [Concept.t()]} | {:error, term()}
  def descendants(code, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    normalized = normalize_code(code)

    children =
      Codes.children(normalized, limit: limit)
      |> Enum.map(fn {child_code, data} -> build_concept(child_code, data) end)

    {:ok, children}
  end

  # ============================================================================
  # ICD-10 Specific Functions
  # ============================================================================

  @doc """
  Validate code format without checking existence.

  Checks if the code matches the ICD-10-CM format pattern.

  ## Examples

      iex> MedOntology.ICD10.valid_format?("E11.9")
      true

      iex> MedOntology.ICD10.valid_format?("E11.99999")
      false

      iex> MedOntology.ICD10.valid_format?("INVALID")
      false

  """
  @spec valid_format?(String.t()) :: boolean()
  def valid_format?(code) when is_binary(code) do
    Regex.match?(@code_pattern, String.upcase(code))
  end

  def valid_format?(_), do: false

  @doc """
  Check if code is billable (has required specificity).

  In ICD-10-CM, billable codes typically have 4-7 characters and
  represent the most specific classification available.

  ## Examples

      iex> MedOntology.ICD10.billable?("E11.9")
      true

      iex> MedOntology.ICD10.billable?("E11")
      false

  """
  @spec billable?(String.t()) :: boolean()
  def billable?(code) when is_binary(code) do
    case lookup(code) do
      {:ok, concept} -> concept.properties[:billable] == true
      _ -> false
    end
  end

  def billable?(_), do: false

  @doc """
  Get the chapter, block, and category hierarchy for a code.

  Returns detailed hierarchy information including chapter, block,
  category, and code details.

  ## Examples

      iex> MedOntology.ICD10.hierarchy("E11.9")
      {:ok, %{
        chapter: "IV",
        chapter_title: "Endocrine, nutritional and metabolic diseases",
        block: "E10-E14",
        block_title: "Diabetes mellitus",
        category: "E11",
        category_title: "Type 2 diabetes mellitus",
        code: "E11.9",
        description: "Type 2 diabetes mellitus without complications",
        billable: true
      }}

  """
  @spec hierarchy(String.t()) :: {:ok, map()} | {:error, term()}
  def hierarchy(code) when is_binary(code) do
    normalized_code = normalize_code(code)

    with {:ok, chapter_info} <- Chapters.find_chapter(normalized_code),
         {:ok, concept} <- lookup(normalized_code) do
      category_code = extract_category(normalized_code)
      block_info = Chapters.find_block(normalized_code)
      category_title = get_category_title(category_code)

      hierarchy_map = %{
        chapter: chapter_info.number,
        chapter_title: chapter_info.title,
        block: get_block_range(block_info),
        block_title: get_block_title(block_info),
        category: category_code,
        category_title: category_title,
        code: concept.code,
        description: concept.display,
        billable: concept.properties[:billable]
      }

      {:ok, hierarchy_map}
    end
  end

  def hierarchy(_), do: {:error, :invalid_code}

  @doc """
  Get codes in a block (e.g., "E10-E14").

  ## Options

    * `:limit` - Maximum number of results (default: 100)

  ## Examples

      iex> MedOntology.ICD10.codes_in_block("E10-E14")
      {:ok, [%Concept{code: "E10", ...}, %Concept{code: "E11", ...}, ...]}

  """
  @spec codes_in_block(String.t(), keyword()) :: {:ok, [Concept.t()]} | {:error, :invalid_block}
  def codes_in_block(block, opts \\ []) when is_binary(block) do
    limit = Keyword.get(opts, :limit, 100)

    case parse_block_range(block) do
      {:ok, start_code, end_code} ->
        codes =
          Codes.in_range(start_code, end_code, limit: limit)
          |> Enum.map(fn {code, data} -> build_concept(code, data) end)

        {:ok, codes}

      :error ->
        {:error, :invalid_block}
    end
  end

  @doc """
  Get excludes1 and excludes2 codes for a code.

  - excludes1: Codes that cannot be coded together (mutually exclusive)
  - excludes2: Codes that may be coded together if documented

  ## Examples

      iex> MedOntology.ICD10.exclusions("E11")
      {:ok, %{
        excludes1: ["diabetes mellitus due to underlying condition (E08.-)"],
        excludes2: []
      }}

  """
  @spec exclusions(String.t()) :: {:ok, map()} | {:error, term()}
  def exclusions(code) when is_binary(code) do
    case lookup(code) do
      {:ok, concept} ->
        {:ok,
         %{
           excludes1: concept.properties[:excludes1] || [],
           excludes2: concept.properties[:excludes2] || []
         }}

      error ->
        error
    end
  end

  def exclusions(_), do: {:error, :invalid_code}

  @doc """
  Get all chapters.

  Returns a list of all ICD-10-CM chapters with their number, title, and range.

  ## Examples

      iex> MedOntology.ICD10.chapters()
      [%{number: "I", title: "Certain infectious and parasitic diseases", range: "A00-B99"}, ...]

  """
  @spec chapters() :: [map()]
  def chapters do
    Chapters.all()
  end

  @doc """
  Check if one code is a more specific version of another (is-a relationship).

  In ICD-10, a code is-a another code if it starts with that code's category.

  ## Examples

      iex> MedOntology.ICD10.is_a?("E11.9", "E11")
      true

      iex> MedOntology.ICD10.is_a?("E11", "E11.9")
      false

  """
  @spec is_a?(String.t(), String.t()) :: boolean()
  def is_a?(child_code, parent_code) when is_binary(child_code) and is_binary(parent_code) do
    child_upper = String.upcase(child_code)
    parent_upper = String.upcase(parent_code)

    # Child is-a parent if child starts with parent and is longer or more specific
    String.starts_with?(child_upper, parent_upper) and
      String.length(child_upper) > String.length(parent_upper)
  end

  def is_a?(_, _), do: false

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp normalize_code(code) when is_binary(code) do
    String.upcase(code) |> String.trim()
  end

  defp exists?(code) do
    normalized = normalize_code(code)
    Codes.exists?(normalized) or cache_hit?(normalized)
  end

  defp cache_hit?(code) do
    case Cache.get(:icd10, code) do
      {:ok, _} -> true
      :miss -> false
    end
  end

  defp build_concept(code, data) when is_map(data) do
    %Concept{
      code: code,
      system: :icd10,
      display: get_data_field(data, :description, code),
      active: true,
      semantic_types: ["diagnosis"],
      properties: %{
        billable: get_data_field(data, :billable, false),
        excludes1: get_data_field(data, :excludes1, []),
        excludes2: get_data_field(data, :excludes2, []),
        includes: get_data_field(data, :includes, [])
      }
    }
  end

  defp get_data_field(data, key, default) do
    data[key] || data[to_string(key)] || default
  end

  defp extract_category(code) do
    # Category is the first 3 characters (letter + 2 digits)
    String.slice(code, 0, 3)
  end

  defp get_category_title(category_code) do
    case Codes.get(category_code) do
      {:ok, data} -> data[:description]
      _ -> nil
    end
  end

  defp get_block_range({:ok, %{range: range}}), do: range
  defp get_block_range(_), do: nil

  defp get_block_title({:ok, %{title: title}}), do: title
  defp get_block_title(_), do: nil

  defp parse_block_range(block) do
    case String.split(block, "-") do
      [start_code, end_code] -> {:ok, start_code, end_code}
      _ -> :error
    end
  end

  defp build_ancestor_list(hierarchy, max_depth) do
    # Add category if different from code
    ancestors =
      if hierarchy.category != hierarchy.code do
        concept =
          Concept.new(hierarchy.category, :icd10, hierarchy.category_title || hierarchy.category)

        [concept]
      else
        []
      end

    # Apply max_depth limit
    case max_depth do
      nil -> Enum.reverse(ancestors)
      depth when is_integer(depth) and depth > 0 -> ancestors |> Enum.reverse() |> Enum.take(depth)
      _ -> []
    end
  end

  defp fetch_from_who(code, opts) do
    case WHO.get_concept(code) do
      {:ok, data} ->
        concept = parse_who_concept(code, data)
        Cache.put(:icd10, code, concept)
        {:ok, maybe_include_extra(concept, opts)}

      {:error, :credentials_not_configured} ->
        {:error, :not_found}

      {:error, :not_found} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  defp parse_who_concept(code, data) do
    title =
      case data["title"] do
        %{"@value" => value} -> value
        title when is_binary(title) -> title
        _ -> code
      end

    %Concept{
      code: code,
      system: :icd10,
      display: title,
      active: true,
      semantic_types: ["diagnosis"],
      properties: %{
        source: :who,
        definition: data["definition"],
        billable: false
      }
    }
  end

  defp maybe_include_extra(concept, _opts) do
    # TODO: Add support for include_relationships and include_mappings
    concept
  end

  defp calculate_search_score(query, display) when is_binary(query) and is_binary(display) do
    query_lower = String.downcase(query)
    display_lower = String.downcase(display)

    cond do
      # Exact match
      display_lower == query_lower ->
        1.0

      # Starts with query
      String.starts_with?(display_lower, query_lower) ->
        0.9

      # Contains query as a word
      String.contains?(display_lower, " #{query_lower} ") or
        String.starts_with?(display_lower, "#{query_lower} ") or
          String.ends_with?(display_lower, " #{query_lower}") ->
        0.85

      # Contains query
      String.contains?(display_lower, query_lower) ->
        0.8

      # Fuzzy match using Jaro distance
      true ->
        String.jaro_distance(query_lower, display_lower)
    end
  end

  defp calculate_search_score(_, _), do: 0.0
end
