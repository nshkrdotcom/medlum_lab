defmodule ClinicalNerEx.Linker.Behaviour do
  @moduledoc """
  Behaviour for entity linkers.

  Each entity type has a corresponding linker that maps extracted
  entities to ontology codes.

  ## Implementing a Linker

  To create a new linker, implement all three callbacks:

      defmodule MyLinker do
        @behaviour ClinicalNerEx.Linker.Behaviour

        @impl true
        def entity_types, do: [:my_entity_type]

        @impl true
        def ontology_systems, do: [:my_ontology]

        @impl true
        def link(%Entity{type: :my_entity_type} = entity) do
          # Perform linking logic
          {:ok, %{entity | ontology_links: [...]}}
        end
        def link(entity), do: {:ok, entity}

        @impl true
        def link_batch(entities) do
          # Batch linking logic
          {:ok, Enum.map(entities, &elem(link(&1), 1))}
        end
      end

  ## Linking Strategy

  For each entity, the linker should:

  1. **Extract searchable text**: Clean the entity text for lookup
  2. **Query med_ontology_ex**: Get candidate concepts
  3. **Rank candidates**: By string similarity, frequency, specificity
  4. **Select best match**: Or top-k for ambiguous cases
  5. **Attach to entity**: As `ontology_links` list
  """

  alias ClinicalNerEx.Entity

  @doc """
  Link an entity to ontology codes.

  Returns the entity with `ontology_links` populated.

  ## Examples

      {:ok, linked_entity} = MyLinker.link(entity)
      linked_entity.ontology_links
      #=> [%{system: :rxnorm, code: "861004", display: "metformin 500mg", confidence: 0.95}]
  """
  @callback link(Entity.t()) :: {:ok, Entity.t()} | {:error, term()}

  @doc """
  Link multiple entities in batch.

  More efficient than calling `link/1` multiple times for large
  entity sets. Implementations should handle grouping by type
  and batching API calls.

  ## Examples

      {:ok, linked_entities} = MyLinker.link_batch(entities)
  """
  @callback link_batch([Entity.t()]) :: {:ok, [Entity.t()]} | {:error, term()}

  @doc """
  Return the entity types this linker handles.

  ## Examples

      MyLinker.entity_types()
      #=> [:medication]
  """
  @callback entity_types() :: [atom()]

  @doc """
  Return the ontology systems this linker uses.

  ## Examples

      MyLinker.ontology_systems()
      #=> [:rxnorm]
  """
  @callback ontology_systems() :: [atom()]
end
