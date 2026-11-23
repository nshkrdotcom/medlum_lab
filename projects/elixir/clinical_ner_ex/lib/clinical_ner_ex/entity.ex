defmodule ClinicalNerEx.Entity do
  @moduledoc """
  Represents an extracted clinical entity.

  ## Fields

  - `id` - Unique identifier for the entity
  - `type` - Entity type (`:medication`, `:lab_value`, `:diagnosis`, `:procedure`, `:temporal`)
  - `text` - The original text span
  - `start_offset` - Character offset where entity starts
  - `end_offset` - Character offset where entity ends
  - `confidence` - Extraction confidence score (0.0 to 1.0)
  - `attributes` - Type-specific attributes (map or struct)
  - `ontology_links` - Links to ontology codes
  - `extraction_method` - Method used for extraction
  - `warnings` - Any warnings about the extraction
  - `metadata` - Additional metadata

  ## Examples

      iex> entity = ClinicalNerEx.Entity.new(%{
      ...>   type: :medication,
      ...>   text: "metformin 500mg",
      ...>   start_offset: 0,
      ...>   end_offset: 15,
      ...>   confidence: 0.95
      ...> })
      iex> entity.type
      :medication
      iex> entity.id != nil
      true
  """

  @type entity_type :: :medication | :lab_value | :diagnosis | :procedure | :temporal | :finding

  @type ontology_link :: %{
          system: :rxnorm | :loinc | :snomed_ct | :icd10 | :cpt,
          code: String.t(),
          display: String.t(),
          confidence: float()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          type: entity_type(),
          text: String.t(),
          start_offset: non_neg_integer(),
          end_offset: non_neg_integer(),
          confidence: float(),
          attributes: map(),
          ontology_links: [ontology_link()],
          extraction_method: :rule_based | :transformer | :hybrid,
          warnings: [String.t()],
          metadata: map()
        }

  defstruct [
    :id,
    :type,
    :text,
    :start_offset,
    :end_offset,
    :confidence,
    attributes: %{},
    ontology_links: [],
    extraction_method: :rule_based,
    warnings: [],
    metadata: %{}
  ]

  @doc """
  Create a new entity with auto-generated ID.

  ## Examples

      iex> entity = ClinicalNerEx.Entity.new(%{type: :medication, text: "aspirin"})
      iex> is_binary(entity.id)
      true
      iex> entity.type
      :medication
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct(__MODULE__, Map.put(attrs, :id, generate_id()))
  end

  @doc """
  Check if entity spans overlap.

  Two entities overlap if their character spans share any characters.

  ## Examples

      iex> e1 = %ClinicalNerEx.Entity{start_offset: 0, end_offset: 10, type: :medication, text: "a"}
      iex> e2 = %ClinicalNerEx.Entity{start_offset: 5, end_offset: 15, type: :diagnosis, text: "b"}
      iex> ClinicalNerEx.Entity.overlaps?(e1, e2)
      true

      iex> e1 = %ClinicalNerEx.Entity{start_offset: 0, end_offset: 10, type: :medication, text: "a"}
      iex> e2 = %ClinicalNerEx.Entity{start_offset: 15, end_offset: 25, type: :diagnosis, text: "b"}
      iex> ClinicalNerEx.Entity.overlaps?(e1, e2)
      false
  """
  @spec overlaps?(t(), t()) :: boolean()
  def overlaps?(%__MODULE__{} = e1, %__MODULE__{} = e2) do
    e1.start_offset < e2.end_offset and e2.start_offset < e1.end_offset
  end

  @doc """
  Check if entity span contains another.

  The outer entity contains the inner entity if the inner entity's
  span is completely within the outer entity's span.

  ## Examples

      iex> outer = %ClinicalNerEx.Entity{start_offset: 0, end_offset: 20, type: :medication, text: "a"}
      iex> inner = %ClinicalNerEx.Entity{start_offset: 5, end_offset: 15, type: :diagnosis, text: "b"}
      iex> ClinicalNerEx.Entity.contains?(outer, inner)
      true

      iex> outer = %ClinicalNerEx.Entity{start_offset: 5, end_offset: 15, type: :medication, text: "a"}
      iex> inner = %ClinicalNerEx.Entity{start_offset: 0, end_offset: 20, type: :diagnosis, text: "b"}
      iex> ClinicalNerEx.Entity.contains?(outer, inner)
      false
  """
  @spec contains?(t(), t()) :: boolean()
  def contains?(%__MODULE__{} = outer, %__MODULE__{} = inner) do
    outer.start_offset <= inner.start_offset and outer.end_offset >= inner.end_offset
  end

  @doc """
  Get entity span length.

  ## Examples

      iex> entity = %ClinicalNerEx.Entity{start_offset: 5, end_offset: 20, type: :medication, text: "a"}
      iex> ClinicalNerEx.Entity.span_length(entity)
      15
  """
  @spec span_length(t()) :: non_neg_integer()
  def span_length(%__MODULE__{} = entity) do
    entity.end_offset - entity.start_offset
  end

  @doc """
  Returns valid entity types.

  ## Examples

      iex> ClinicalNerEx.Entity.valid_types()
      [:medication, :lab_value, :diagnosis, :procedure, :temporal, :finding]
  """
  @spec valid_types() :: [entity_type()]
  def valid_types do
    [:medication, :lab_value, :diagnosis, :procedure, :temporal, :finding]
  end

  @doc """
  Checks if the given type is a valid entity type.

  ## Examples

      iex> ClinicalNerEx.Entity.valid_type?(:medication)
      true

      iex> ClinicalNerEx.Entity.valid_type?(:invalid)
      false
  """
  @spec valid_type?(atom()) :: boolean()
  def valid_type?(type) do
    type in valid_types()
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
