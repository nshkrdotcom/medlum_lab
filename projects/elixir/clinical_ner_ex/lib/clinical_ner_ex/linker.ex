defmodule ClinicalNerEx.Linker do
  @moduledoc """
  Main entry point for ontology linking.

  Links extracted entities to medical ontology codes using type-specific linkers.
  This module orchestrates the linking process and provides convenience functions
  for direct ontology lookups.

  ## Usage

      # Link a single entity
      {:ok, linked_entity} = ClinicalNerEx.Linker.link(entity)

      # Link multiple entities
      {:ok, linked_entities} = ClinicalNerEx.Linker.link_all(entities)

      # Direct linking functions
      {:ok, concept} = ClinicalNerEx.Linker.link_medication("metformin 500mg")
      {:ok, concept} = ClinicalNerEx.Linker.link_lab("hemoglobin A1c")
      {:ok, codes} = ClinicalNerEx.Linker.link_diagnosis("type 2 diabetes")
      {:ok, concept} = ClinicalNerEx.Linker.link_procedure("colonoscopy")

  ## Entity Type to Ontology Mapping

  | Entity Type | Primary Ontology | Secondary Ontology |
  |-------------|------------------|-------------------|
  | `:medication` | RxNorm | - |
  | `:lab_value` | LOINC | - |
  | `:diagnosis` | SNOMED-CT | ICD-10 |
  | `:procedure` | SNOMED-CT | - |
  | `:temporal` | - | - |

  ## Configuration

  Ontology linking can be disabled globally:

      config :clinical_ner_ex,
        enable_ontology_linking: false

  ## Telemetry Events

  The linker emits the following telemetry events:

  - `[:clinical_ner_ex, :linker, :cache_hit]` - Cache hit for linking
  - `[:clinical_ner_ex, :linker, :cache_miss]` - Cache miss for linking
  """

  alias ClinicalNerEx.Entity
  alias ClinicalNerEx.Linker.{RxNorm, LOINC, SNOMED, ICD10}
  alias ClinicalNerEx.Config

  @linkers %{
    medication: [RxNorm],
    lab_value: [LOINC],
    diagnosis: [SNOMED, ICD10],
    procedure: [SNOMED],
    temporal: []
  }

  @doc """
  Link an entity to ontology codes.

  Automatically selects appropriate linkers based on entity type.
  Linking can be disabled via configuration.

  ## Examples

      entity = %Entity{type: :medication, text: "metformin 500mg", ...}
      {:ok, linked} = ClinicalNerEx.Linker.link(entity)
      linked.ontology_links
      #=> [%{system: :rxnorm, code: "861004", display: "metformin...", confidence: 0.95}]

  ## Options

  This function uses the global `enable_ontology_linking` configuration.
  When disabled, returns the entity unchanged.
  """
  @spec link(Entity.t()) :: {:ok, Entity.t()} | {:error, term()}
  def link(%Entity{type: type} = entity) do
    if Config.enable_ontology_linking?() do
      linkers = Map.get(@linkers, type, [])
      apply_linkers(entity, linkers)
    else
      {:ok, entity}
    end
  end

  @doc """
  Link all entities in a list.

  Processes each entity through the appropriate linkers based on entity type.

  ## Examples

      entities = [
        %Entity{type: :medication, text: "metformin"},
        %Entity{type: :lab_value, text: "glucose"},
        %Entity{type: :diagnosis, text: "diabetes"}
      ]

      {:ok, linked_entities} = ClinicalNerEx.Linker.link_all(entities)
  """
  @spec link_all([Entity.t()]) :: {:ok, [Entity.t()]}
  def link_all(entities) do
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

  @doc """
  Link a medication string directly to RxNorm.

  This is a convenience function for direct medication lookups without
  creating an Entity first.

  ## Examples

      {:ok, concept} = ClinicalNerEx.Linker.link_medication("metformin 500mg")
      concept.code
      #=> "861004"

      {:error, :not_found} = ClinicalNerEx.Linker.link_medication("notamedication")
  """
  @spec link_medication(String.t()) :: {:ok, map()} | {:error, :not_found | :ontology_unavailable}
  def link_medication(medication_text) do
    if Code.ensure_loaded?(MedOntology) and
         function_exported?(MedOntology.RxNorm, :normalize, 1) do
      apply(MedOntology.RxNorm, :normalize, [medication_text])
    else
      {:error, :ontology_unavailable}
    end
  end

  @doc """
  Link a lab name directly to LOINC.

  This is a convenience function for direct lab lookups without
  creating an Entity first.

  ## Examples

      {:ok, concept} = ClinicalNerEx.Linker.link_lab("hemoglobin A1c")
      concept.code
      #=> "4548-4"

      {:error, :not_found} = ClinicalNerEx.Linker.link_lab("unknownlab")
  """
  @spec link_lab(String.t()) :: {:ok, map()} | {:error, :not_found | :ontology_unavailable}
  def link_lab(lab_name) do
    if Code.ensure_loaded?(MedOntology) and function_exported?(MedOntology, :search, 3) do
      case apply(MedOntology, :search, [:loinc, lab_name, [limit: 1]]) do
        {:ok, [match | _]} -> {:ok, match.concept}
        {:ok, []} -> {:error, :not_found}
        error -> error
      end
    else
      {:error, :ontology_unavailable}
    end
  end

  @doc """
  Link a diagnosis text to SNOMED-CT and ICD-10.

  Returns both SNOMED-CT and ICD-10 codes when available.

  ## Examples

      {:ok, codes} = ClinicalNerEx.Linker.link_diagnosis("type 2 diabetes")
      codes.snomed_ct
      #=> %{code: "44054006", display: "Type 2 diabetes mellitus"}
      codes.icd10
      #=> %{code: "E11.9", display: "Type 2 diabetes mellitus without complications"}

      {:error, :not_found} = ClinicalNerEx.Linker.link_diagnosis("unknowncondition")
  """
  @spec link_diagnosis(String.t()) :: {:ok, map()} | {:error, :not_found | :ontology_unavailable}
  def link_diagnosis(diagnosis_text) do
    if Code.ensure_loaded?(MedOntology) and function_exported?(MedOntology, :search, 3) do
      snomed_result = apply(MedOntology, :search, [:snomed_ct, diagnosis_text, [limit: 1]])
      icd10_result = apply(MedOntology, :search, [:icd10, diagnosis_text, [limit: 1]])

      snomed =
        case snomed_result do
          {:ok, [m | _]} -> %{code: m.concept.code, display: m.concept.display}
          _ -> nil
        end

      icd10 =
        case icd10_result do
          {:ok, [m | _]} -> %{code: m.concept.code, display: m.concept.display}
          _ -> nil
        end

      if snomed || icd10 do
        {:ok, %{snomed_ct: snomed, icd10: icd10}}
      else
        {:error, :not_found}
      end
    else
      {:error, :ontology_unavailable}
    end
  end

  @doc """
  Link a procedure text to SNOMED-CT.

  This is a convenience function for direct procedure lookups without
  creating an Entity first.

  ## Examples

      {:ok, concept} = ClinicalNerEx.Linker.link_procedure("colonoscopy")
      concept.code
      #=> "73761001"

      {:error, :not_found} = ClinicalNerEx.Linker.link_procedure("unknownprocedure")
  """
  @spec link_procedure(String.t()) :: {:ok, map()} | {:error, :not_found | :ontology_unavailable}
  def link_procedure(procedure_text) do
    if Code.ensure_loaded?(MedOntology) and function_exported?(MedOntology, :search, 3) do
      opts = [limit: 1, semantic_types: ["procedure"]]

      case apply(MedOntology, :search, [:snomed_ct, procedure_text, opts]) do
        {:ok, [match | _]} -> {:ok, match.concept}
        {:ok, []} -> {:error, :not_found}
        error -> error
      end
    else
      {:error, :ontology_unavailable}
    end
  end

  @doc """
  Returns the linker modules for a given entity type.

  ## Examples

      ClinicalNerEx.Linker.linkers_for(:medication)
      #=> [ClinicalNerEx.Linker.RxNorm]

      ClinicalNerEx.Linker.linkers_for(:diagnosis)
      #=> [ClinicalNerEx.Linker.SNOMED, ClinicalNerEx.Linker.ICD10]

      ClinicalNerEx.Linker.linkers_for(:temporal)
      #=> []
  """
  @spec linkers_for(atom()) :: [module()]
  def linkers_for(entity_type) do
    Map.get(@linkers, entity_type, [])
  end

  @doc """
  Returns all supported entity type to linker mappings.

  ## Examples

      ClinicalNerEx.Linker.all_linkers()
      #=> %{medication: [...], lab_value: [...], ...}
  """
  @spec all_linkers() :: map()
  def all_linkers, do: @linkers

  # Private functions

  defp apply_linkers(entity, linkers) do
    Enum.reduce_while(linkers, {:ok, entity}, fn linker, {:ok, ent} ->
      case linker.link(ent) do
        {:ok, linked} -> {:cont, {:ok, linked}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
