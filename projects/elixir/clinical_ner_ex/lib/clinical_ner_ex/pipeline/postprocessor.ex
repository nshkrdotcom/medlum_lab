defmodule ClinicalNerEx.Pipeline.Postprocessor do
  @moduledoc """
  Post-processing for extracted entities.

  Handles span overlap resolution, deduplication, and confidence filtering
  to produce a clean, non-overlapping set of extracted entities.

  ## Processing Steps

  1. **Overlap resolution** - Handle overlapping entity spans
  2. **Deduplication** - Remove duplicate entities
  3. **Confidence filtering** - Filter by confidence threshold
  4. **Sorting** - Sort by document position

  ## Overlap Resolution Strategy

  When two entities overlap, the postprocessor keeps the "better" one based on:
  1. Higher confidence score (with 0.1 tolerance)
  2. Longer span length
  3. More extracted attributes

  ## Examples

      entities = [
        %Entity{type: :medication, start_offset: 0, end_offset: 15, confidence: 0.9},
        %Entity{type: :medication, start_offset: 5, end_offset: 20, confidence: 0.8}
      ]

      {:ok, processed} = Postprocessor.process(entities, 0.7)
      # Returns single best entity, filtered by confidence
  """

  alias ClinicalNerEx.Entity

  @doc """
  Process extracted entities.

  Applies overlap resolution, deduplication, and confidence filtering.

  ## Parameters

  - `entities` - List of extracted entities
  - `confidence_threshold` - Minimum confidence to include (0.0-1.0)

  ## Returns

  - `{:ok, [Entity.t()]}` - Processed list of entities

  ## Examples

      iex> entities = [%Entity{type: :medication, confidence: 0.9, start_offset: 0, end_offset: 10}]
      iex> {:ok, result} = Postprocessor.process(entities, 0.7)
      iex> length(result)
      1
  """
  @spec process([Entity.t()], float()) :: {:ok, [Entity.t()]}
  def process(entities, confidence_threshold) when is_list(entities) do
    processed =
      entities
      |> resolve_overlaps()
      |> deduplicate()
      |> filter_confidence(confidence_threshold)
      |> sort_by_offset()

    {:ok, processed}
  end

  @doc """
  Resolve overlapping entity spans.

  When entities overlap, keeps the "better" one based on confidence,
  span length, and attribute completeness.

  ## Examples

      iex> e1 = %Entity{start_offset: 0, end_offset: 10, confidence: 0.9, type: :medication, text: "a", attributes: %{}}
      iex> e2 = %Entity{start_offset: 5, end_offset: 15, confidence: 0.8, type: :medication, text: "b", attributes: %{}}
      iex> result = Postprocessor.resolve_overlaps([e1, e2])
      iex> length(result)
      1
  """
  @spec resolve_overlaps([Entity.t()]) :: [Entity.t()]
  def resolve_overlaps(entities) do
    # Sort by start offset, then by end offset (descending) to prefer longer spans
    entities
    |> Enum.sort_by(&{&1.start_offset, -&1.end_offset})
    |> Enum.reduce([], fn entity, acc ->
      case find_overlapping(entity, acc) do
        nil ->
          # No overlap, add entity
          [entity | acc]

        existing ->
          # Found overlap, decide which to keep
          if should_replace?(existing, entity) do
            acc = List.delete(acc, existing)
            [entity | acc]
          else
            acc
          end
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Remove duplicate entities.

  Entities are considered duplicates if they have the same type,
  start offset, and end offset.

  ## Examples

      iex> e1 = %Entity{type: :medication, start_offset: 0, end_offset: 10, text: "a"}
      iex> e2 = %Entity{type: :medication, start_offset: 0, end_offset: 10, text: "a"}
      iex> result = Postprocessor.deduplicate([e1, e2])
      iex> length(result)
      1
  """
  @spec deduplicate([Entity.t()]) :: [Entity.t()]
  def deduplicate(entities) do
    entities
    |> Enum.uniq_by(fn e ->
      {e.type, e.start_offset, e.end_offset}
    end)
  end

  @doc """
  Filter entities by confidence threshold.

  ## Examples

      iex> e1 = %Entity{confidence: 0.9, type: :medication, text: "a"}
      iex> e2 = %Entity{confidence: 0.5, type: :medication, text: "b"}
      iex> result = Postprocessor.filter_confidence([e1, e2], 0.7)
      iex> length(result)
      1
  """
  @spec filter_confidence([Entity.t()], float()) :: [Entity.t()]
  def filter_confidence(entities, threshold) do
    Enum.filter(entities, fn e -> e.confidence >= threshold end)
  end

  @doc """
  Sort entities by their position in the document.

  ## Examples

      iex> e1 = %Entity{start_offset: 10, type: :medication, text: "a"}
      iex> e2 = %Entity{start_offset: 0, type: :medication, text: "b"}
      iex> result = Postprocessor.sort_by_offset([e1, e2])
      iex> hd(result).start_offset
      0
  """
  @spec sort_by_offset([Entity.t()]) :: [Entity.t()]
  def sort_by_offset(entities) do
    Enum.sort_by(entities, & &1.start_offset)
  end

  # Private functions

  defp find_overlapping(entity, entities) do
    Enum.find(entities, fn e -> Entity.overlaps?(e, entity) end)
  end

  defp should_replace?(existing, candidate) do
    # Decide if candidate should replace existing
    # Prefer: higher confidence, longer span, more attributes

    cond do
      # Significantly higher confidence wins (with 0.1 tolerance)
      candidate.confidence > existing.confidence + 0.1 ->
        true

      # Longer span wins (if confidence is similar)
      Entity.span_length(candidate) > Entity.span_length(existing) and
          candidate.confidence >= existing.confidence - 0.1 ->
        true

      # More attributes wins (if span is similar)
      map_size(candidate.attributes) > map_size(existing.attributes) and
          abs(Entity.span_length(candidate) - Entity.span_length(existing)) < 3 ->
        true

      true ->
        false
    end
  end
end
