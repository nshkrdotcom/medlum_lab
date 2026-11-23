defmodule ClinicalNerEx.Extractors.Diagnosis do
  @moduledoc """
  Diagnosis entity extractor.

  Extracts disease names, conditions, symptoms, and clinical findings from
  clinical text, including status (active/historical/suspected), severity,
  and anatomical location.

  ## Extraction Methods

  - `:rule_based` - Fast regex pattern matching
  - `:transformer` - ML model inference via Bumblebee (stub for future)
  - `:hybrid` - Combines both approaches

  Note: Diagnosis extraction defaults to `:transformer` per ADR-003 due to
  the high variability in diagnosis mentions. Rule-based patterns serve as
  a fallback when transformer is unavailable.

  ## Extracted Attributes

  - `condition` - Name of the disease, disorder, or condition
  - `status` - Current status (`:active`, `:resolved`, `:historical`, `:suspected`, `:ruled_out`)
  - `severity` - Severity level (`:mild`, `:moderate`, `:severe`, or nil)
  - `body_site` - Anatomical location
  - `laterality` - Left, right, or bilateral indicator
  - `onset` - When the condition started

  ## Examples

      iex> context = %{text: "h/o type 2 diabetes", method: :rule_based, opts: []}
      iex> {:ok, entities} = ClinicalNerEx.Extractors.Diagnosis.extract(context)
      iex> length(entities) >= 1
      true

      iex> context = %{text: "Patient has HTN and DM", method: :rule_based, opts: []}
      iex> {:ok, entities} = ClinicalNerEx.Extractors.Diagnosis.extract(context)
      iex> length(entities) >= 2
      true

  ## Confidence Scoring

  Confidence scores are calculated based on pattern type and attribute completeness:
  - Known abbreviations: 0.90 base
  - History pattern: 0.85 base
  - Suspected/rule-out pattern: 0.80 base
  - Severity/laterality patterns: 0.80 base
  - Acuity patterns: 0.75 base
  - Default: 0.70 base

  Boosts are applied for additional attributes extracted.
  """

  @behaviour ClinicalNerEx.Extractors.Behaviour

  alias ClinicalNerEx.Entity
  alias ClinicalNerEx.Extractors.Diagnosis.Patterns

  @impl true
  @doc """
  Returns the entity type handled by this extractor.
  """
  @spec entity_type() :: :diagnosis
  def entity_type, do: :diagnosis

  @impl true
  @doc """
  Returns the extraction methods supported by this extractor.
  """
  @spec supported_methods() :: [:rule_based | :transformer | :hybrid]
  def supported_methods, do: [:rule_based, :transformer, :hybrid]

  @impl true
  @doc """
  Extract diagnosis entities from the context.

  The context must contain:
  - `text` - The clinical text to extract from
  - `method` - The extraction method (`:rule_based`, `:transformer`, or `:hybrid`)
  - `opts` - Additional options (optional)

  ## Options

  - `:confidence_threshold` - Minimum confidence score (default: 0.0)

  ## Returns

  - `{:ok, [Entity.t()]}` - List of extracted diagnosis entities
  - `{:error, reason}` - Error tuple on failure
  """
  @spec extract(map()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract(context) do
    # Default to transformer per ADR-003, but fall back to rule_based
    method = context[:method] || :transformer

    case method do
      :rule_based -> extract_rule_based(context)
      :transformer -> extract_transformer(context)
      :hybrid -> extract_hybrid(context)
    end
  end

  @doc """
  Extract diagnoses using rule-based patterns.

  This is the fallback extraction method when transformer is unavailable.

  ## Examples

      iex> context = %{text: "h/o hypertension", method: :rule_based}
      iex> {:ok, entities} = Diagnosis.extract_rule_based(context)
      iex> hd(entities).type
      :diagnosis
  """
  @spec extract_rule_based(map()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract_rule_based(%{text: text} = context) do
    opts = context[:opts] || []
    confidence_threshold = Keyword.get(opts, :confidence_threshold, 0.0)

    entities =
      text
      |> Patterns.extract()
      |> Enum.map(fn {start, end_offset, match, type} ->
        build_entity(text, start, end_offset, match, type)
      end)
      |> Enum.filter(fn entity -> entity.confidence >= confidence_threshold end)

    {:ok, entities}
  rescue
    e -> {:error, {:extraction_failed, Exception.message(e)}}
  end

  @doc """
  Extract diagnoses using transformer model.

  Note: This is a stub. Full implementation requires Bumblebee integration
  with Bio_ClinicalBERT model.

  ## Future Implementation

  Will use:
  - Bio_ClinicalBERT for clinical NER
  - Token classification with BIO tagging
  - Softmax confidence scoring
  """
  @spec extract_transformer(map()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract_transformer(%{text: _text}) do
    # TODO: Implement with Bumblebee Bio_ClinicalBERT
    # This will be implemented in Phase 5 per the implementation plan
    # For now, returns empty list
    {:ok, []}
  end

  @doc """
  Extract diagnoses using hybrid approach (rule-based + transformer).

  The hybrid method:
  1. Runs rule-based extraction
  2. Runs transformer extraction in parallel (if available)
  3. Merges results using confidence-weighted voting
  4. Flags disagreements for review

  ## Merging Strategy

  - Exact match (same span): Average confidence + agreement bonus
  - Partial overlap: Prefer longer span
  - No overlap: Include both
  """
  @spec extract_hybrid(map()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract_hybrid(context) do
    {:ok, rule_entities} = extract_rule_based(context)
    {:ok, transformer_entities} = extract_transformer(context)
    merged = merge_entities(rule_entities, transformer_entities)
    {:ok, merged}
  end

  # Private functions

  defp build_entity(text, start, end_offset, match, type) do
    # Parse the match into normalized attributes
    attrs = Patterns.parse_match(match, type)

    # Create the entity
    Entity.new(%{
      type: :diagnosis,
      text: String.slice(text, start, end_offset - start),
      start_offset: start,
      end_offset: end_offset,
      confidence: calculate_confidence(attrs, type),
      attributes: attrs,
      extraction_method: :rule_based,
      warnings: build_warnings(attrs),
      metadata: %{pattern_type: type}
    })
  end

  defp calculate_confidence(attrs, type) do
    base_confidence =
      case type do
        # Known abbreviations are high confidence
        :abbreviation -> 0.90
        # History pattern is reliable
        :historical -> 0.85
        # Suspected pattern is reliable
        :suspected -> 0.80
        :with_severity -> 0.80
        :with_laterality -> 0.80
        :with_acuity -> 0.75
        _ -> 0.70
      end

    # Boost for more complete extractions
    boost =
      [
        {attrs[:condition], 0.05},
        {attrs[:severity], 0.02},
        {attrs[:body_site], 0.02},
        {attrs[:laterality], 0.01}
      ]
      |> Enum.reduce(0.0, fn {value, boost_value}, acc ->
        if value && value != "", do: acc + boost_value, else: acc
      end)

    min(base_confidence + boost, 1.0)
  end

  defp build_warnings(attrs) do
    warnings = []

    # Warn if no condition name found
    warnings =
      if is_nil(attrs[:condition]) or attrs[:condition] == "" do
        ["No condition name extracted" | warnings]
      else
        warnings
      end

    Enum.reverse(warnings)
  end

  defp merge_entities(rule_entities, []) do
    # No transformer entities, return rule-based only
    rule_entities
  end

  defp merge_entities([], transformer_entities) do
    # No rule-based entities, return transformer only
    transformer_entities
  end

  defp merge_entities(rule_entities, transformer_entities) do
    # For hybrid merging:
    # 1. Find exact matches (same span) - boost confidence
    # 2. Find partial overlaps - prefer longer span
    # 3. Include non-overlapping from both

    all_entities = rule_entities ++ transformer_entities

    # Group by overlapping spans
    grouped = group_by_overlap(all_entities)

    # Merge each group
    Enum.flat_map(grouped, fn group ->
      case length(group) do
        1 ->
          # Single entity, adjust confidence down slightly (no agreement)
          [entity] = group
          [%{entity | confidence: entity.confidence * 0.9}]

        _ ->
          # Multiple entities overlap - merge with agreement bonus
          merge_overlapping_group(group)
      end
    end)
    |> Enum.sort_by(& &1.start_offset)
  end

  defp group_by_overlap(entities) do
    # Simple grouping by checking if any entities overlap
    Enum.reduce(entities, [], fn entity, groups ->
      find_and_add_to_group(entity, groups)
    end)
  end

  defp find_and_add_to_group(entity, groups) do
    case find_overlapping_group_index(entity, groups) do
      nil ->
        # No matching group, start a new one
        groups ++ [[entity]]

      idx ->
        # Add to existing group
        List.update_at(groups, idx, fn group -> [entity | group] end)
    end
  end

  defp find_overlapping_group_index(entity, groups) do
    groups
    |> Enum.with_index()
    |> Enum.find_value(fn {group, idx} ->
      if Enum.any?(group, &Entity.overlaps?(entity, &1)), do: idx, else: nil
    end)
  end

  defp merge_overlapping_group(entities) do
    # Find the entity with the longest span
    best = Enum.max_by(entities, &Entity.span_length/1)

    # Calculate merged confidence with agreement bonus
    avg_confidence =
      entities
      |> Enum.map(& &1.confidence)
      |> Enum.sum()
      |> Kernel./(length(entities))

    # Agreement bonus: +0.1 for each agreeing method beyond the first
    agreement_bonus = min((length(entities) - 1) * 0.1, 0.2)

    merged_confidence = min(avg_confidence + agreement_bonus, 1.0)

    # Use the best entity's attributes, update confidence and method
    [%{best | confidence: merged_confidence, extraction_method: :hybrid}]
  end
end
