defmodule ClinicalNerEx.Linker.SNOMED do
  @moduledoc """
  Links diagnosis and procedure entities to SNOMED-CT codes.

  This linker uses `med_ontology_ex` to link clinical diagnoses and procedures
  to SNOMED-CT (Systematized Nomenclature of Medicine - Clinical Terms).

  ## Example

      entity = %Entity{
        type: :diagnosis,
        text: "type 2 diabetes",
        attributes: %{condition: "type 2 diabetes", status: :active}
      }

      {:ok, linked} = ClinicalNerEx.Linker.SNOMED.link(entity)
      linked.ontology_links
      #=> [%{system: :snomed_ct, code: "44054006", display: "Type 2 diabetes mellitus", confidence: 0.95}]

  ## Linking Strategy

  1. Extract condition/procedure name from structured attributes or raw text
  2. Check cache for existing linking results
  3. Query MedOntology.search/3 with semantic type filters
  4. Use search score as confidence basis
  """

  @behaviour ClinicalNerEx.Linker.Behaviour

  alias ClinicalNerEx.Entity
  alias ClinicalNerEx.Cache

  @impl true
  def entity_types, do: [:diagnosis, :procedure]

  @impl true
  def ontology_systems, do: [:snomed_ct]

  @impl true
  def link(%Entity{type: type} = entity) when type in [:diagnosis, :procedure] do
    query = build_query(entity)

    cache_key = {:snomed_ct, type, query}

    case Cache.get(:linker_cache, cache_key) do
      {:ok, links} ->
        emit_telemetry(:cache_hit, type)
        {:ok, %{entity | ontology_links: links}}

      :miss ->
        emit_telemetry(:cache_miss, type)
        perform_link(entity, query, cache_key, type)
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

  defp build_query(%Entity{type: :diagnosis, attributes: attrs, text: text}) do
    condition = attrs[:condition] || attrs["condition"]
    condition || text
  end

  defp build_query(%Entity{type: :procedure, attributes: attrs, text: text}) do
    procedure_name = attrs[:procedure_name] || attrs["procedure_name"]
    procedure_name || text
  end

  defp build_query(%Entity{text: text}), do: text

  defp perform_link(entity, query, cache_key, type) do
    if Code.ensure_loaded?(MedOntology) and function_exported?(MedOntology, :search, 3) do
      semantic_types =
        case type do
          :diagnosis -> ["disorder", "finding"]
          :procedure -> ["procedure"]
          _ -> []
        end

      opts = [limit: 3, semantic_types: semantic_types]

      case apply(MedOntology, :search, [:snomed_ct, query, opts]) do
        {:ok, [best | _rest]} ->
          link = %{
            system: :snomed_ct,
            code: best.concept.code,
            display: best.concept.display,
            confidence: best.score
          }

          links = [link]
          Cache.put(:linker_cache, cache_key, links)
          {:ok, %{entity | ontology_links: links}}

        {:ok, []} ->
          {:ok, add_warning(entity, "No SNOMED-CT match for: #{query}")}

        {:error, _reason} ->
          {:ok, add_warning(entity, "SNOMED-CT lookup failed")}
      end
    else
      {:ok, add_warning(entity, "SNOMED-CT linking unavailable")}
    end
  end

  defp add_warning(entity, warning) do
    %{entity | warnings: [warning | entity.warnings]}
  end

  defp emit_telemetry(event, entity_type) do
    :telemetry.execute(
      [:clinical_ner_ex, :linker, event],
      %{count: 1},
      %{entity_type: entity_type, system: :snomed_ct}
    )
  end
end
