defmodule MedlumLlm.Detectors.ClinicalPII do
  @moduledoc """
  Clinical PII detector for HIPAA-covered medical identifiers.

  Implements the `LlmGuard.Detector` behaviour to detect medical-specific
  personally identifiable information including:

  - Medical Record Numbers (MRN)
  - Dates of Birth (DOB)
  - National Provider Identifiers (NPI)
  - DEA Numbers
  - Medical service dates
  - Insurance/Medicare IDs
  - Room/bed numbers
  - Provider names
  - Facility names

  ## Detection Strategy

  Uses a tiered pattern matching approach:
  - **Tier 1**: High confidence patterns (MRN, DOB, NPI, DEA)
  - **Tier 2**: Medium confidence patterns (dates, insurance, room/bed)
  - **Tier 3**: Lower confidence patterns (names, facilities)

  Context keywords near detected patterns boost confidence scores.

  ## Usage

  Add to LlmGuard configuration via `enabled_detectors`:

      config = LlmGuard.Config.new(
        enabled_detectors: [MedlumLlm.Detectors.ClinicalPII]
      )

  ## Options

  - `:confidence_threshold` - Minimum confidence to report (default: 0.7)
  - `:include_tier_3` - Include name/facility patterns (default: false)
  - `:pii_types` - List of specific types to detect (default: all)

  ## Examples

      iex> {:detected, result} = MedlumLlm.Detectors.ClinicalPII.detect("MRN: 12345678")
      iex> :mrn in result.patterns_matched
      true

      iex> {:detected, result} = MedlumLlm.Detectors.ClinicalPII.detect("DOB: 01/15/1980")
      iex> result.confidence > 0.9
      true

      iex> {:safe, _} = MedlumLlm.Detectors.ClinicalPII.detect("Normal clinical text")
  """

  @behaviour LlmGuard.Detector

  alias MedlumLlm.Detectors.ClinicalPII.Patterns

  @type detection :: %{
          type: atom(),
          confidence: float(),
          span: {non_neg_integer(), non_neg_integer()},
          text: String.t()
        }

  @impl true
  @spec name() :: String.t()
  def name, do: "clinical_pii"

  @impl true
  @spec description() :: String.t()
  def description, do: "Detects clinical/healthcare PII patterns (HIPAA compliance)"

  @impl true
  @spec detect(String.t(), keyword()) ::
          {:safe, map()} | {:detected, map()}
  def detect(input, opts) when is_binary(input) do
    confidence_threshold = Keyword.get(opts, :confidence_threshold, 0.7)
    include_tier_3 = Keyword.get(opts, :include_tier_3, false)
    pii_types = Keyword.get(opts, :pii_types)

    patterns = get_patterns(include_tier_3, pii_types)

    detections =
      patterns
      |> Enum.flat_map(&detect_pattern(&1, input))
      |> deduplicate_overlapping()
      |> Enum.filter(&(&1.confidence >= confidence_threshold))
      |> Enum.sort_by(& &1.confidence, :desc)

    if Enum.empty?(detections) do
      {:safe, %{message: "No clinical PII detected"}}
    else
      detected_types = detections |> Enum.map(& &1.type) |> Enum.uniq()

      {:detected,
       %{
         confidence: calculate_combined_confidence(detections),
         category: :clinical_phi,
         patterns_matched: detected_types,
         metadata: %{
           detection_count: length(detections),
           detections: sanitize_detections(detections),
           types: detected_types
         }
       }}
    end
  end

  @doc """
  Scans text and returns all clinical PII detections with positions.

  Unlike `detect/2`, this returns detailed position information for each
  detection, useful for redaction.

  ## Options

  - `:include_tier_3` - Include name/facility patterns (default: false)
  - `:confidence_threshold` - Minimum confidence (default: 0.5)

  ## Examples

      iex> detections = MedlumLlm.Detectors.ClinicalPII.scan("MRN: 12345678, DOB: 01/15/1980")
      iex> length(detections)
      2
  """
  @spec scan(String.t(), keyword()) :: [detection()]
  def scan(input, opts \\ []) when is_binary(input) do
    include_tier_3 = Keyword.get(opts, :include_tier_3, false)
    confidence_threshold = Keyword.get(opts, :confidence_threshold, 0.5)

    patterns = get_patterns(include_tier_3, nil)

    patterns
    |> Enum.flat_map(&detect_pattern(&1, input))
    |> deduplicate_overlapping()
    |> Enum.filter(&(&1.confidence >= confidence_threshold))
    |> Enum.sort_by(&elem(&1.span, 0))
  end

  @doc """
  Quick check if text contains any clinical PHI.

  More efficient than `detect/2` when you only need a boolean result.

  ## Examples

      iex> MedlumLlm.Detectors.ClinicalPII.contains_phi?("MRN: 12345678")
      true

      iex> MedlumLlm.Detectors.ClinicalPII.contains_phi?("Normal text")
      false
  """
  @spec contains_phi?(String.t(), keyword()) :: boolean()
  def contains_phi?(input, opts \\ []) when is_binary(input) do
    include_tier_3 = Keyword.get(opts, :include_tier_3, false)

    patterns = get_patterns(include_tier_3, nil)

    Enum.any?(patterns, fn pattern ->
      case Regex.run(pattern.regex, input) do
        nil -> false
        _ -> true
      end
    end)
  end

  # Private functions

  defp get_patterns(include_tier_3, pii_types) do
    base_patterns =
      if include_tier_3 do
        Patterns.all_patterns()
      else
        Patterns.standard_patterns()
      end

    case pii_types do
      nil -> base_patterns
      types when is_list(types) -> Enum.filter(base_patterns, &(&1.type in types))
    end
  end

  defp detect_pattern(pattern, input) do
    case Regex.scan(pattern.regex, input, return: :index) do
      [] ->
        []

      matches ->
        context_boost = calculate_context_boost(input, pattern)
        confidence = min(1.0, pattern.base_confidence + context_boost)

        Enum.map(matches, fn match ->
          # Get the full match (first element in the list)
          {start, length} = hd(match)

          %{
            type: pattern.type,
            confidence: confidence,
            span: {start, start + length},
            text: String.slice(input, start, length)
          }
        end)
    end
  end

  defp calculate_context_boost(input, pattern) do
    if Enum.empty?(pattern.context_keywords) do
      0.0
    else
      input_lower = String.downcase(input)

      if Enum.any?(pattern.context_keywords, &String.contains?(input_lower, &1)) do
        pattern.context_boost
      else
        0.0
      end
    end
  end

  defp calculate_combined_confidence(detections) do
    # Use max confidence with a small boost for multiple detections
    max_conf = Enum.max_by(detections, & &1.confidence).confidence
    count_boost = min(0.05, (length(detections) - 1) * 0.01)
    min(1.0, max_conf + count_boost)
  end

  defp sanitize_detections(detections) do
    # Return detection info without the actual PII values
    Enum.map(detections, fn d ->
      %{
        type: d.type,
        confidence: d.confidence,
        position: d.span
      }
    end)
  end

  defp deduplicate_overlapping(detections) do
    detections
    |> Enum.sort_by(fn d -> {elem(d.span, 0), -(elem(d.span, 1) - elem(d.span, 0))} end)
    |> Enum.reduce([], fn detection, acc ->
      if Enum.any?(acc, &overlaps?(&1, detection)) do
        acc
      else
        [detection | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp overlaps?(d1, d2) do
    {s1, e1} = d1.span
    {s2, e2} = d2.span
    not (e1 <= s2 or e2 <= s1)
  end
end
