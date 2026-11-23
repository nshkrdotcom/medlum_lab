defmodule MedOntology.LOINC do
  @moduledoc """
  LOINC ontology operations for laboratory and clinical observations.

  LOINC (Logical Observation Identifiers Names and Codes) provides unique
  identifiers for lab tests and clinical observations. It contains ~100,000
  codes and is the universal standard for identifying laboratory and clinical
  observations.

  ## LOINC Code Structure

  LOINC codes consist of a numeric portion followed by a hyphen and check digit.
  The code represents six parts (axes):

    * **Component** - The analyte/observable (e.g., "Glucose")
    * **Property** - What is measured (e.g., "MCnc" for mass concentration)
    * **Time aspect** - Point in time vs interval (e.g., "Pt" for point)
    * **System** - Specimen type (e.g., "Ser/Plas" for serum or plasma)
    * **Scale type** - Quantitative, ordinal, nominal, narrative (e.g., "Qn")
    * **Method type** - Optional measurement method (e.g., "HPLC")

  ## Examples

      # Lookup a code
      MedOntology.LOINC.lookup("2345-7")
      # => {:ok, %Concept{code: "2345-7", display: "Glucose [Mass/volume] in Serum or Plasma"}}

      # Get LOINC parts
      MedOntology.LOINC.parts("2345-7")
      # => {:ok, %{component: "Glucose", property: "MCnc", ...}}

      # Get reference range
      MedOntology.LOINC.reference_range("2345-7")
      # => {:ok, %{low: 70, high: 100, unit: "mg/dL"}}

      # Evaluate a lab value
      MedOntology.LOINC.evaluate_value("2345-7", 150)
      # => {:ok, :high}

      # Get panel members
      MedOntology.LOINC.panel_members("24323-8")
      # => {:ok, [%Concept{code: "2345-7"}, ...]}

      # Check if code is a panel
      MedOntology.LOINC.panel?("24323-8")
      # => true

      # Search by component
      MedOntology.LOINC.search("hemoglobin")
      # => {:ok, [%SearchResult{concept: %Concept{...}, score: 0.95, ...}]}

  ## Configuration

  The LOINC FHIR API requires authentication:

      config :med_ontology_ex,
        loinc_username: System.get_env("LOINC_USERNAME"),
        loinc_password: System.get_env("LOINC_PASSWORD")

  """

  @behaviour MedOntology.Ontology

  alias MedOntology.Cache.Server, as: Cache
  alias MedOntology.{Concept, SearchResult}
  alias MedOntology.LOINC.{Panels, ReferenceRanges}

  # Use configurable client for testability
  defp loinc_client do
    Application.get_env(:med_ontology_ex, :loinc_client, MedOntology.Client.LOINC)
  end

  @doc """
  Look up a LOINC code.

  Returns the LOINC concept with its display name, parts, and properties.

  ## Options

    * `:include_relationships` - Include related concepts (default: false)
    * `:include_mappings` - Include cross-ontology mappings (default: false)

  ## Examples

      iex> MedOntology.LOINC.lookup("2345-7")
      {:ok, %Concept{code: "2345-7", display: "Glucose [Mass/volume] in Serum or Plasma"}}

      iex> MedOntology.LOINC.lookup("invalid")
      {:error, :not_found}

  """
  @impl true
  @spec lookup(String.t(), keyword()) :: {:ok, Concept.t()} | {:error, term()}
  def lookup(code, opts \\ []) do
    _include_relationships = Keyword.get(opts, :include_relationships, false)
    _include_mappings = Keyword.get(opts, :include_mappings, false)

    start_time = System.monotonic_time()

    case Cache.get(:loinc, code) do
      {:ok, concept} ->
        emit_telemetry(:lookup, code, start_time, cache_hit: true)
        {:ok, concept}

      :miss ->
        case fetch_and_cache(code) do
          {:ok, concept} ->
            emit_telemetry(:lookup, code, start_time, cache_hit: false)
            {:ok, concept}

          error ->
            error
        end
    end
  end

  @doc """
  Search LOINC codes by component name or description.

  ## Options

    * `:limit` - Maximum results (default: 25)
    * `:active_only` - Only return active concepts (default: true)

  ## Examples

      iex> MedOntology.LOINC.search("hemoglobin")
      {:ok, [
        %SearchResult{
          concept: %Concept{code: "718-7", display: "Hemoglobin [Mass/volume] in Blood"},
          score: 0.95,
          matched_term: "Hemoglobin [Mass/volume] in Blood"
        }
      ]}

  """
  @impl true
  @spec search(String.t(), keyword()) :: {:ok, [SearchResult.t()]} | {:error, term()}
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    _active_only = Keyword.get(opts, :active_only, true)

    with {:ok, items} <- loinc_client().search(query, limit: limit) do
      results =
        items
        |> Enum.map(fn item ->
          concept = %Concept{
            code: item["code"],
            system: :loinc,
            display: item["display"]
          }

          score = calculate_search_score(query, concept.display)
          %SearchResult{concept: concept, score: score, matched_term: concept.display}
        end)
        |> Enum.sort_by(& &1.score, :desc)
        |> Enum.take(limit)

      {:ok, results}
    end
  end

  @doc """
  Check if a LOINC code is valid.

  Validates both the format (numeric with check digit) and existence.

  ## Examples

      iex> MedOntology.LOINC.valid?("2345-7")
      true

      iex> MedOntology.LOINC.valid?("invalid")
      false

  """
  @impl true
  @spec valid?(String.t()) :: boolean()
  def valid?(code) do
    # First check format: digits, hyphen, check digit
    if Regex.match?(~r/^\d+-\d$/, code) do
      # Then verify existence
      case lookup(code) do
        {:ok, _} -> true
        _ -> false
      end
    else
      false
    end
  end

  @doc """
  Get ancestor concepts.

  LOINC does not have a traditional hierarchy like SNOMED-CT.
  This function returns an empty list.

  ## Examples

      iex> MedOntology.LOINC.ancestors("2345-7")
      {:ok, []}

  """
  @impl true
  @spec ancestors(String.t(), keyword()) :: {:ok, [Concept.t()]} | {:error, term()}
  def ancestors(_code, _opts \\ []) do
    {:ok, []}
  end

  @doc """
  Get descendant concepts.

  LOINC does not have a traditional hierarchy like SNOMED-CT.
  This function returns an empty list.

  ## Examples

      iex> MedOntology.LOINC.descendants("2345-7")
      {:ok, []}

  """
  @impl true
  @spec descendants(String.t(), keyword()) :: {:ok, [Concept.t()]} | {:error, term()}
  def descendants(_code, _opts \\ []) do
    {:ok, []}
  end

  @doc """
  Get LOINC parts for a code (the 6-part axis).

  Returns the six components that define a LOINC code:

    * `:component` - The analyte/observable
    * `:property` - What is measured (concentration, mass, etc.)
    * `:time_aspect` - Point in time vs time interval
    * `:system` - Specimen type (serum, plasma, etc.)
    * `:scale_type` - Quantitative, ordinal, nominal, narrative
    * `:method_type` - Optional measurement method

  ## Examples

      iex> MedOntology.LOINC.parts("4548-4")
      {:ok, %{
        component: "Hemoglobin A1c",
        property: "MFr",
        time_aspect: "Pt",
        system: "Bld",
        scale_type: "Qn",
        method_type: nil
      }}

  """
  @spec parts(String.t()) :: {:ok, map()} | {:error, term()}
  def parts(code) do
    case lookup(code) do
      {:ok, concept} ->
        {:ok,
         %{
           component: concept.properties[:component],
           property: concept.properties[:property],
           time_aspect: concept.properties[:time_aspect],
           system: concept.properties[:system],
           scale_type: concept.properties[:scale_type],
           method_type: concept.properties[:method_type]
         }}

      error ->
        error
    end
  end

  @doc """
  Get reference range for a LOINC code.

  Note: LOINC itself has limited reference range data.
  This uses default ranges for common tests.

  ## Examples

      iex> MedOntology.LOINC.reference_range("4548-4")
      {:ok, %{name: "Hemoglobin A1c", low: 4.0, high: 5.6, unit: "%"}}

      iex> MedOntology.LOINC.reference_range("unknown")
      {:error, :not_available}

  """
  @spec reference_range(String.t()) :: {:ok, map()} | {:error, :not_available}
  def reference_range(code) do
    ReferenceRanges.get(code)
  end

  @doc """
  Evaluate a lab value against reference range.

  ## Returns

    * `:normal` - Within reference range
    * `:low` - Below low threshold
    * `:high` - Above high threshold
    * `:critical_low` - Below critical low threshold
    * `:critical_high` - Above critical high threshold

  ## Examples

      iex> MedOntology.LOINC.evaluate_value("4548-4", 7.2)
      {:ok, :high}

      iex> MedOntology.LOINC.evaluate_value("4548-4", 5.0)
      {:ok, :normal}

      iex> MedOntology.LOINC.evaluate_value("2345-7", 35)
      {:ok, :critical_low}

  """
  @spec evaluate_value(String.t(), number()) :: {:ok, atom()} | {:error, :not_available}
  def evaluate_value(code, value) do
    ReferenceRanges.evaluate(code, value)
  end

  @doc """
  Search LOINC by component name.

  Alias for search/2.

  ## Examples

      iex> MedOntology.LOINC.by_component("hemoglobin")
      {:ok, [%SearchResult{concept: %Concept{code: "718-7"}, ...}]}

  """
  @spec by_component(String.t(), keyword()) :: {:ok, [SearchResult.t()]} | {:error, term()}
  def by_component(component, opts \\ []) do
    search(component, opts)
  end

  @doc """
  Get panel members for a LOINC panel code.

  Returns the component tests that make up a laboratory panel.

  ## Examples

      iex> MedOntology.LOINC.panel_members("24323-8")
      {:ok, [%Concept{code: "2345-7", display: "Glucose"}, ...]}

      iex> MedOntology.LOINC.panel_members("2345-7")
      {:error, :not_found}

  """
  @spec panel_members(String.t()) :: {:ok, [Concept.t()]} | {:error, term()}
  def panel_members(panel_code) do
    # First check local panel definitions
    case Panels.get(panel_code) do
      {:ok, panel} ->
        concepts = Enum.map(panel.components, &lookup_component/1)
        {:ok, concepts}

      {:error, :not_found} ->
        # Fall back to FHIR ValueSet expansion
        fetch_panel_from_api(panel_code)
    end
  end

  defp lookup_component(code) do
    case lookup(code) do
      {:ok, concept} -> concept
      _ -> %Concept{code: code, system: :loinc, display: code}
    end
  end

  @doc """
  Check if the code represents a laboratory panel.

  ## Examples

      iex> MedOntology.LOINC.panel?("24323-8")
      true

      iex> MedOntology.LOINC.panel?("2345-7")
      false

  """
  @spec panel?(String.t()) :: boolean()
  def panel?(code) do
    Panels.panel?(code)
  end

  @doc """
  Get panel information.

  Returns the panel name, description, and component codes.

  ## Examples

      iex> MedOntology.LOINC.panel_info("24323-8")
      {:ok, %{name: "Basic Metabolic Panel (BMP)", components: [...], description: "..."}}

  """
  @spec panel_info(String.t()) :: {:ok, map()} | {:error, :not_found}
  def panel_info(panel_code) do
    Panels.get(panel_code)
  end

  @doc """
  Gets the class/category for a LOINC code.

  ## Examples

      iex> MedOntology.LOINC.class("2345-7")
      {:ok, "CHEM"}

  """
  @spec class(String.t()) :: {:ok, String.t()} | {:error, term()}
  def class(code) do
    case lookup(code) do
      {:ok, concept} ->
        case concept.properties[:class] do
          nil -> {:error, :not_available}
          class_value -> {:ok, class_value}
        end

      error ->
        error
    end
  end

  @doc """
  Find panels containing a specific component.

  ## Examples

      iex> MedOntology.LOINC.panels_with_component("2345-7")
      [{"24323-8", "Basic Metabolic Panel (BMP)"}, {"24325-3", "Comprehensive Metabolic Panel (CMP)"}]

  """
  @spec panels_with_component(String.t()) :: [{String.t(), String.t()}]
  def panels_with_component(component_code) do
    Panels.panels_with_component(component_code)
  end

  # Private functions

  defp fetch_and_cache(code) do
    with {:ok, data} <- loinc_client().get_concept(code) do
      concept = parse_fhir_concept(code, data)
      Cache.put(:loinc, code, concept)
      {:ok, concept}
    end
  end

  defp parse_fhir_concept(code, data) do
    %Concept{
      code: code,
      system: :loinc,
      display: data["display"] || data["name"],
      synonyms: [data["SHORTNAME"]] |> Enum.filter(& &1),
      active: data["STATUS"] != "DEPRECATED",
      semantic_types: [data["CLASS"]] |> Enum.filter(& &1),
      properties: %{
        component: data["COMPONENT"],
        property: data["PROPERTY"],
        time_aspect: data["TIME_ASPCT"],
        system: data["SYSTEM"],
        scale_type: data["SCALE_TYP"],
        method_type: data["METHOD_TYP"],
        class: data["CLASS"],
        classtype: data["CLASSTYPE"],
        order_obs: data["ORDER_OBS"],
        units: data["EXAMPLE_UNITS"]
      }
    }
  end

  defp fetch_panel_from_api(panel_code) do
    case loinc_client().get_panel_members(panel_code) do
      {:ok, items} ->
        concepts =
          Enum.map(items, fn item ->
            %Concept{
              code: item["code"],
              system: :loinc,
              display: item["display"]
            }
          end)

        {:ok, concepts}

      error ->
        error
    end
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

  defp emit_telemetry(operation, code, start_time, metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:med_ontology, operation, :stop],
      %{duration: duration},
      Map.merge(%{ontology: :loinc, code: code}, Map.new(metadata))
    )
  end
end
