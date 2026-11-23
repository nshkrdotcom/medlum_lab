defmodule ClinicalNerEx.Extractors.Medication do
  @moduledoc """
  Medication entity extractor.

  Extracts drug names, doses, frequencies, routes, and other medication-related
  information from clinical text. This is the most critical extractor for the
  CVL Medication Agent.

  ## Extraction Methods

  - `:rule_based` - Fast regex pattern matching (< 10ms)
  - `:transformer` - ML model inference via Bumblebee (stub for future)
  - `:hybrid` - Combines both approaches (default)

  ## Extracted Attributes

  - `drug_name` - Generic or brand name of the medication
  - `dose` - Numeric dose value
  - `dose_unit` - Unit of measurement (mg, mcg, mL, etc.)
  - `frequency` - How often taken (BID, daily, q8h, etc.)
  - `route` - Administration route (PO, IV, SC, etc.)
  - `duration` - Length of therapy
  - `prn` - Whether medication is "as needed"

  ## Examples

      iex> context = %{text: "metformin 500mg PO BID", method: :rule_based, opts: []}
      iex> {:ok, entities} = ClinicalNerEx.Extractors.Medication.extract(context)
      iex> length(entities)
      1
      iex> hd(entities).attributes.drug_name
      "metformin"

      iex> context = %{text: "Patient on lisinopril 10mg daily and aspirin 81mg", method: :rule_based, opts: []}
      iex> {:ok, entities} = ClinicalNerEx.Extractors.Medication.extract(context)
      iex> length(entities)
      2

  ## Confidence Scoring

  Confidence scores are calculated based on extraction completeness:
  - Drug name found: +0.15
  - Dose found: +0.10
  - Dose unit found: +0.05
  - Route found: +0.05
  - Frequency found: +0.05

  Base confidence is 0.6, with a maximum of 1.0.
  """

  @behaviour ClinicalNerEx.Extractors.Behaviour

  alias ClinicalNerEx.Entity
  alias ClinicalNerEx.Extractors.Medication.Patterns

  @impl true
  @doc """
  Returns the entity type handled by this extractor.
  """
  @spec entity_type() :: :medication
  def entity_type, do: :medication

  @impl true
  @doc """
  Returns the extraction methods supported by this extractor.
  """
  @spec supported_methods() :: [:rule_based | :transformer | :hybrid]
  def supported_methods, do: [:rule_based, :transformer, :hybrid]

  @impl true
  @doc """
  Extract medication entities from the context.

  The context must contain:
  - `text` - The clinical text to extract from
  - `method` - The extraction method (`:rule_based`, `:transformer`, or `:hybrid`)
  - `opts` - Additional options (optional)

  ## Options

  - `:confidence_threshold` - Minimum confidence score (default: 0.0)
  - `:validate_drug_names` - Check drug names against dictionary (default: false)

  ## Returns

  - `{:ok, [Entity.t()]}` - List of extracted medication entities
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
  Extract medications using rule-based patterns.

  This is the primary extraction method, using regex patterns to identify
  medication mentions in clinical text.

  ## Examples

      iex> context = %{text: "metformin 500mg PO BID", method: :rule_based}
      iex> {:ok, entities} = Medication.extract_rule_based(context)
      iex> hd(entities).type
      :medication
  """
  @spec extract_rule_based(map()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract_rule_based(%{text: text} = context) do
    opts = context[:opts] || []
    confidence_threshold = Keyword.get(opts, :confidence_threshold, 0.0)

    entities =
      text
      |> Patterns.extract()
      |> Enum.map(fn {start, end_offset, match} ->
        build_entity(text, start, end_offset, match)
      end)
      |> Enum.filter(fn entity -> entity.confidence >= confidence_threshold end)

    {:ok, entities}
  rescue
    e -> {:error, {:extraction_failed, Exception.message(e)}}
  end

  @doc """
  Extract medications using transformer model.

  Note: This is a stub. Full implementation requires Bumblebee integration
  with Med7 or Bio_ClinicalBERT models.

  ## Future Implementation

  Will use:
  - Med7 model for medication-specific NER
  - Bio_ClinicalBERT for general clinical NER
  - Token classification with BIO tagging
  """
  @spec extract_transformer(map()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract_transformer(%{text: _text}) do
    # TODO: Implement with Bumblebee Med7 or Bio_ClinicalBERT
    # This will be implemented in Phase 5 (Week 7-8) per the implementation plan
    {:ok, []}
  end

  @doc """
  Extract medications using hybrid approach (rule-based + transformer).

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

  defp build_entity(text, start, end_offset, match) do
    # Parse the match into normalized attributes
    attrs = Patterns.parse_match(match)

    # Check for PRN in surrounding context (up to 20 chars after match)
    context_end = min(end_offset + 20, String.length(text))
    surrounding_text = String.slice(text, start, context_end - start)
    prn = Patterns.prn?(surrounding_text)

    # Check for duration in surrounding context (up to 30 chars after match)
    duration_end = min(end_offset + 30, String.length(text))
    duration_text = String.slice(text, start, duration_end - start)
    duration = Patterns.extract_duration(duration_text)

    # Build final attributes
    attrs = Map.put(attrs, :prn, prn)
    attrs = if duration, do: Map.put(attrs, :duration, duration), else: attrs

    # Create the entity
    Entity.new(%{
      type: :medication,
      text: String.slice(text, start, end_offset - start),
      start_offset: start,
      end_offset: end_offset,
      confidence: calculate_confidence(attrs),
      attributes: attrs,
      extraction_method: :rule_based,
      warnings: build_warnings(attrs),
      metadata: %{pattern_type: :full}
    })
  end

  defp calculate_confidence(attrs) do
    base_confidence = 0.60

    # Boost confidence for more complete extractions
    boost =
      [
        {attrs[:drug_name], 0.15},
        {attrs[:dose], 0.10},
        {attrs[:dose_unit], 0.05},
        {attrs[:route], 0.05},
        {attrs[:frequency], 0.05}
      ]
      |> Enum.reduce(0.0, fn {value, boost}, acc ->
        if value && value != "", do: acc + boost, else: acc
      end)

    min(base_confidence + boost, 1.0)
  end

  defp build_warnings(attrs) do
    warnings = []

    # Warn if no drug name found
    warnings =
      if is_nil(attrs[:drug_name]) or attrs[:drug_name] == "" do
        ["No drug name extracted" | warnings]
      else
        warnings
      end

    # Warn if dose found but no unit
    warnings =
      if attrs[:dose] && (is_nil(attrs[:dose_unit]) or attrs[:dose_unit] == "") do
        ["Dose found without unit" | warnings]
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
