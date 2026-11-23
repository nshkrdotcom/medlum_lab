defmodule ClinicalNerEx.Linker.ICD10 do
  @moduledoc """
  Links diagnosis entities to ICD-10-CM codes.

  This linker uses `med_ontology_ex` to link clinical diagnoses to
  ICD-10-CM (International Classification of Diseases, 10th Revision,
  Clinical Modification).

  ICD-10 is typically a secondary ontology for diagnoses, with SNOMED-CT
  being the primary clinical terminology. This linker appends ICD-10 codes
  to existing ontology links.

  ## Example

      entity = %Entity{
        type: :diagnosis,
        text: "type 2 diabetes",
        attributes: %{condition: "type 2 diabetes"},
        ontology_links: [%{system: :snomed_ct, code: "44054006", ...}]
      }

      {:ok, linked} = ClinicalNerEx.Linker.ICD10.link(entity)
      linked.ontology_links
      #=> [
      #=>   %{system: :snomed_ct, code: "44054006", ...},
      #=>   %{system: :icd10, code: "E11.9", display: "Type 2 diabetes...", confidence: 0.90}
      #=> ]

  ## Linking Strategy

  1. Extract condition name from structured attributes or raw text
  2. Check cache for existing linking results
  3. Query MedOntology.search/3 for ICD-10 matches
  4. Append to existing ontology_links (does not replace)
  5. Silent on no match (ICD-10 is secondary, no warnings)
  """

  @behaviour ClinicalNerEx.Linker.Behaviour

  alias ClinicalNerEx.Entity
  alias ClinicalNerEx.Cache

  @impl true
  def entity_types, do: [:diagnosis]

  @impl true
  def ontology_systems, do: [:icd10]

  @impl true
  def link(%Entity{type: :diagnosis} = entity) do
    query = build_query(entity)

    cache_key = {:icd10, query}

    case Cache.get(:linker_cache, cache_key) do
      {:ok, links} ->
        emit_telemetry(:cache_hit, :diagnosis)
        {:ok, %{entity | ontology_links: entity.ontology_links ++ links}}

      :miss ->
        emit_telemetry(:cache_miss, :diagnosis)
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
    condition = attrs[:condition] || attrs["condition"]
    condition || text
  end

  defp perform_link(entity, query, cache_key) do
    if Code.ensure_loaded?(MedOntology) and function_exported?(MedOntology, :search, 3) do
      case apply(MedOntology, :search, [:icd10, query, [limit: 3]]) do
        {:ok, [best | _rest]} ->
          link = %{
            system: :icd10,
            code: best.concept.code,
            display: best.concept.display,
            confidence: best.score
          }

          links = [link]
          Cache.put(:linker_cache, cache_key, links)
          {:ok, %{entity | ontology_links: entity.ontology_links ++ links}}

        {:ok, []} ->
          # Don't warn for ICD-10 - it's secondary to SNOMED-CT
          {:ok, entity}

        {:error, _reason} ->
          # Silent failure for secondary ontology
          {:ok, entity}
      end
    else
      # Silent when unavailable - ICD-10 is secondary
      {:ok, entity}
    end
  end

  defp emit_telemetry(event, entity_type) do
    :telemetry.execute(
      [:clinical_ner_ex, :linker, event],
      %{count: 1},
      %{entity_type: entity_type, system: :icd10}
    )
  end
end
