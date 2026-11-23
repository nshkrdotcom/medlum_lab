defmodule ClinicalNerEx.Linker.LOINC do
  @moduledoc """
  Links lab value entities to LOINC codes.

  This linker uses `med_ontology_ex` to link laboratory test names to
  LOINC (Logical Observation Identifiers Names and Codes).

  ## Example

      entity = %Entity{
        type: :lab_value,
        text: "Hemoglobin A1c 7.5%",
        attributes: %{lab_name: "Hemoglobin A1c", value: 7.5, unit: "%"}
      }

      {:ok, linked} = ClinicalNerEx.Linker.LOINC.link(entity)
      linked.ontology_links
      #=> [%{system: :loinc, code: "4548-4", display: "Hemoglobin A1c...", confidence: 0.92}]

  ## Linking Strategy

  1. Extract lab name from structured attributes or raw text
  2. Check cache for existing linking results
  3. Query MedOntology.search/3 for LOINC matches
  4. Use search score as confidence basis
  """

  @behaviour ClinicalNerEx.Linker.Behaviour

  alias ClinicalNerEx.Entity
  alias ClinicalNerEx.Cache

  @impl true
  def entity_types, do: [:lab_value]

  @impl true
  def ontology_systems, do: [:loinc]

  @impl true
  def link(%Entity{type: :lab_value} = entity) do
    query = build_query(entity)

    cache_key = {:loinc, query}

    case Cache.get(:linker_cache, cache_key) do
      {:ok, links} ->
        emit_telemetry(:cache_hit, :lab_value)
        {:ok, %{entity | ontology_links: links}}

      :miss ->
        emit_telemetry(:cache_miss, :lab_value)
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
    lab_name = attrs[:lab_name] || attrs["lab_name"]
    lab_name || text
  end

  defp perform_link(entity, query, cache_key) do
    if Code.ensure_loaded?(MedOntology) and function_exported?(MedOntology, :search, 3) do
      case apply(MedOntology, :search, [:loinc, query, [limit: 3]]) do
        {:ok, [best | _rest]} ->
          link = %{
            system: :loinc,
            code: best.concept.code,
            display: best.concept.display,
            confidence: best.score
          }

          links = [link]
          Cache.put(:linker_cache, cache_key, links)
          {:ok, %{entity | ontology_links: links}}

        {:ok, []} ->
          {:ok, add_warning(entity, "No LOINC match for: #{query}")}

        {:error, _reason} ->
          {:ok, add_warning(entity, "LOINC lookup failed")}
      end
    else
      {:ok, add_warning(entity, "LOINC linking unavailable")}
    end
  end

  defp add_warning(entity, warning) do
    %{entity | warnings: [warning | entity.warnings]}
  end

  defp emit_telemetry(event, entity_type) do
    :telemetry.execute(
      [:clinical_ner_ex, :linker, event],
      %{count: 1},
      %{entity_type: entity_type, system: :loinc}
    )
  end
end
