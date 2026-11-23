defmodule ClinicalNerEx.Extractors.LabValue do
  @moduledoc """
  Lab value entity extractor.

  Extracts laboratory test names, values, units, reference ranges, and abnormal
  flags from clinical text. This is critical for the CVL Lab Agent to verify
  lab-related claims.

  ## Extraction Methods

  - `:rule_based` - Fast regex pattern matching (< 10ms)
  - `:transformer` - ML model inference via Bumblebee (stub for future)
  - `:hybrid` - Combines both approaches (default)

  ## Extracted Attributes

  - `lab_name` - Name of the laboratory test (normalized to canonical form)
  - `value` - Numeric result value
  - `unit` - Unit of measurement (normalized)
  - `reference_low` - Lower bound of normal range (when available)
  - `reference_high` - Upper bound of normal range (when available)
  - `abnormal_flag` - Abnormality indicator (H, L, HH, LL)
  - `timestamp` - When the test was collected (future)
  - `specimen` - Specimen type (future)

  ## Pattern Types

  The extractor recognizes several patterns:

  1. **Lab with reference range**: "WBC 8.5 (4.5-11.0)"
  2. **Lab with value and unit**: "Creatinine 1.2 mg/dL"
  3. **Lab with abnormal flag**: "Glucose 250 mg/dL (H)"
  4. **Electrolyte shorthand**: "Na 138, K 4.2, Cl 102"
  5. **Percentage values**: "A1c 7.2%"

  ## Examples

      iex> context = %{text: "A1c 7.2% (H)", method: :rule_based, opts: []}
      iex> {:ok, entities} = ClinicalNerEx.Extractors.LabValue.extract(context)
      iex> length(entities)
      1
      iex> hd(entities).attributes.lab_name
      "hemoglobin a1c"
      iex> hd(entities).attributes.value
      7.2

      iex> context = %{text: "Labs: Na 138, K 4.2, Cl 102", method: :rule_based, opts: []}
      iex> {:ok, entities} = ClinicalNerEx.Extractors.LabValue.extract(context)
      iex> length(entities)
      3

  ## Confidence Scoring

  Confidence scores are calculated based on extraction completeness:
  - Base confidence: 0.70-0.85 depending on pattern type
  - Lab name found: +0.05
  - Unit found: +0.03
  - Reference range found: +0.05
  - Abnormal flag found: +0.02

  Maximum confidence is 1.0.
  """

  @behaviour ClinicalNerEx.Extractors.Behaviour

  alias ClinicalNerEx.Entity
  alias ClinicalNerEx.Extractors.LabValue.Patterns

  @impl true
  @doc """
  Returns the entity type handled by this extractor.
  """
  @spec entity_type() :: :lab_value
  def entity_type, do: :lab_value

  @impl true
  @doc """
  Returns the extraction methods supported by this extractor.
  """
  @spec supported_methods() :: [:rule_based | :transformer | :hybrid]
  def supported_methods, do: [:rule_based, :transformer, :hybrid]

  @impl true
  @doc """
  Extract lab value entities from the context.

  The context must contain:
  - `text` - The clinical text to extract from
  - `method` - The extraction method (`:rule_based`, `:transformer`, or `:hybrid`)
  - `opts` - Additional options (optional)

  ## Options

  - `:confidence_threshold` - Minimum confidence score (default: 0.0)
  - `:validate_lab_names` - Check lab names against dictionary (default: true)

  ## Returns

  - `{:ok, [Entity.t()]}` - List of extracted lab value entities
  - `{:error, reason}` - Error tuple on failure
  """
  @spec extract(map()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract(context) do
    method = context[:method] || :rule_based

    case method do
      :rule_based -> extract_rule_based(context)
      :transformer -> extract_transformer(context)
      :hybrid -> extract_hybrid(context)
    end
  end

  @doc """
  Extract lab values using rule-based patterns.

  This is the primary extraction method, using regex patterns to identify
  lab value mentions in clinical text.

  ## Examples

      iex> context = %{text: "Hemoglobin 14.5 g/dL", method: :rule_based}
      iex> {:ok, entities} = LabValue.extract_rule_based(context)
      iex> hd(entities).type
      :lab_value
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
  Extract lab values using transformer model.

  Note: This is a stub. Full implementation requires Bumblebee integration
  with Bio_ClinicalBERT or similar clinical NER models.

  ## Future Implementation

  Will use:
  - Bio_ClinicalBERT for clinical NER
  - Token classification with BIO tagging
  - Entity-specific post-processing
  """
  @spec extract_transformer(map()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract_transformer(%{text: _text}) do
    # TODO: Implement with Bumblebee Bio_ClinicalBERT
    # This will be implemented in Phase 5 (Week 7-8) per the implementation plan
    {:ok, []}
  end

  @doc """
  Extract lab values using hybrid approach (rule-based + transformer).

  The hybrid method:
  1. Runs rule-based extraction (fast, high precision)
  2. Runs transformer extraction in parallel (if available)
  3. Merges results using confidence-weighted voting
  4. Flags disagreements for review

  ## Merging Strategy

  - Exact match (same span): Average confidence + agreement bonus
  - Partial overlap: Prefer transformer span
  - No overlap: Include both
  """
  @spec extract_hybrid(map()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract_hybrid(context) do
    # Run rule-based extraction
    {:ok, rule_entities} = extract_rule_based(context)

    # Run transformer extraction (if available)
    {:ok, transformer_entities} = extract_transformer(context)

    # Merge results with confidence adjustment
    merged = merge_entities(rule_entities, transformer_entities)

    {:ok, merged}
  end

  # Private functions

  defp build_entity(text, start, end_offset, match, type) do
    # Parse the match into normalized attributes
    attrs = Patterns.parse_match(match, type)

    # Create the entity
    Entity.new(%{
      type: :lab_value,
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
    # Base confidence varies by pattern type
    base_confidence =
      case type do
        :with_reference -> 0.85
        :percentage -> 0.82
        :electrolyte -> 0.80
        :standard -> 0.75
      end

    # Boost confidence for more complete extractions
    boost =
      [
        {attrs[:lab_name], 0.05},
        {attrs[:unit], 0.03},
        {attrs[:reference_low] && attrs[:reference_high], 0.05},
        {attrs[:abnormal_flag], 0.02}
      ]
      |> Enum.reduce(0.0, fn {value, boost_val}, acc ->
        if value && value != "" && value != false do
          acc + boost_val
        else
          acc
        end
      end)

    min(base_confidence + boost, 1.0)
  end

  defp build_warnings(attrs) do
    warnings = []

    # Warn if no lab name found
    warnings =
      if is_nil(attrs[:lab_name]) or attrs[:lab_name] == "" do
        ["No lab name extracted" | warnings]
      else
        warnings
      end

    # Warn if value found but no unit
    warnings =
      if attrs[:value] && (is_nil(attrs[:unit]) or attrs[:unit] == "") do
        ["Value found without unit" | warnings]
      else
        warnings
      end

    # Warn about potential abnormal values if flag is present
    warnings =
      if attrs[:abnormal_flag] in ["HH", "LL"] do
        ["Critical value flag detected" | warnings]
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
