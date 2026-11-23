defmodule ClinicalNerEx.Linker.RxNorm do
  @moduledoc """
  Links medication entities to RxNorm codes.

  This linker uses `med_ontology_ex` to normalize medication names and
  link them to RxNorm concept identifiers (CUIs).

  ## Example

      entity = %Entity{
        type: :medication,
        text: "metformin 500mg",
        attributes: %{drug_name: "metformin", dose: 500, dose_unit: "mg"}
      }

      {:ok, linked} = ClinicalNerEx.Linker.RxNorm.link(entity)
      linked.ontology_links
      #=> [%{system: :rxnorm, code: "861004", display: "metformin...", confidence: 0.95}]

  ## Linking Strategy

  1. Build search query from structured attributes (preferred) or raw text
  2. Check cache for existing linking results
  3. Query MedOntology.RxNorm.normalize/1 for exact match
  4. Fall back to MedOntology.search/3 for fuzzy matching
  5. Calculate confidence based on string similarity
  """

  @behaviour ClinicalNerEx.Linker.Behaviour

  alias ClinicalNerEx.Entity
  alias ClinicalNerEx.Cache

  @impl true
  def entity_types, do: [:medication]

  @impl true
  def ontology_systems, do: [:rxnorm]

  @impl true
  def link(%Entity{type: :medication} = entity) do
    # Build search query from medication attributes
    query = build_query(entity)

    # Check cache first
    cache_key = {:rxnorm, query}

    case Cache.get(:linker_cache, cache_key) do
      {:ok, links} ->
        emit_telemetry(:cache_hit, :medication)
        {:ok, %{entity | ontology_links: links}}

      :miss ->
        emit_telemetry(:cache_miss, :medication)
        perform_link(entity, query, cache_key)
    end
  end

  def link(entity), do: {:ok, entity}

  @impl true
  def link_batch(entities) do
    linked =
      Enum.map(entities, fn entity ->
        with {:ok, linked} <- link(entity) do
          linked
        else
          _ -> entity
        end
      end)

    {:ok, linked}
  end

  # Private functions

  defp build_query(%Entity{attributes: attrs, text: text}) do
    # Prefer structured attributes over raw text
    drug_name = attrs[:drug_name] || attrs["drug_name"]
    dose = attrs[:dose] || attrs["dose"]
    dose_unit = attrs[:dose_unit] || attrs["dose_unit"]

    cond do
      drug_name && dose && dose_unit ->
        "#{drug_name} #{dose}#{dose_unit}"

      drug_name ->
        drug_name

      true ->
        text
    end
  end

  defp perform_link(entity, query, cache_key) do
    # Check if med_ontology_ex is available
    if Code.ensure_loaded?(MedOntology) and function_exported?(MedOntology.RxNorm, :normalize, 1) do
      case apply(MedOntology.RxNorm, :normalize, [query]) do
        {:ok, concept} ->
          link = %{
            system: :rxnorm,
            code: concept.code,
            display: concept.display,
            confidence: calculate_confidence(query, concept)
          }

          links = [link]
          Cache.put(:linker_cache, cache_key, links)
          {:ok, %{entity | ontology_links: links}}

        {:error, :not_found} ->
          # Try search instead
          try_search(entity, query, cache_key)

        {:error, _reason} ->
          # Try search on other errors too
          try_search(entity, query, cache_key)
      end
    else
      # med_ontology_ex not available
      {:ok, add_warning(entity, "RxNorm linking unavailable")}
    end
  end

  defp try_search(entity, query, cache_key) do
    if Code.ensure_loaded?(MedOntology) and function_exported?(MedOntology, :search, 3) do
      case apply(MedOntology, :search, [:rxnorm, query, [limit: 3]]) do
        {:ok, [best | _rest]} ->
          link = %{
            system: :rxnorm,
            code: best.concept.code,
            display: best.concept.display,
            # Reduce confidence for search matches
            confidence: best.score * 0.8
          }

          links = [link]
          Cache.put(:linker_cache, cache_key, links)
          {:ok, %{entity | ontology_links: links}}

        {:ok, []} ->
          {:ok, add_warning(entity, "No RxNorm match for: #{query}")}

        {:error, _reason} ->
          {:ok, add_warning(entity, "RxNorm lookup failed")}
      end
    else
      {:ok, add_warning(entity, "RxNorm search unavailable")}
    end
  end

  defp calculate_confidence(query, concept) do
    query_lower = String.downcase(query)
    display_lower = String.downcase(concept.display)

    similarity = String.jaro_distance(query_lower, display_lower)
    # Boost for successful match, cap at 1.0
    min(similarity + 0.1, 1.0)
  end

  defp add_warning(entity, warning) do
    %{entity | warnings: [warning | entity.warnings]}
  end

  defp emit_telemetry(event, entity_type) do
    :telemetry.execute(
      [:clinical_ner_ex, :linker, event],
      %{count: 1},
      %{entity_type: entity_type, system: :rxnorm}
    )
  end
end
