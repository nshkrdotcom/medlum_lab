defmodule ClinicalNerEx.Extractors.Temporal do
  @moduledoc """
  Temporal expression extractor.

  Extracts dates, times, durations, and relative temporal expressions
  from clinical text.

  ## Extraction Methods

  - `:rule_based` - Fast regex pattern matching (primary method)
  - `:transformer` - ML model inference (stub for future)
  - `:hybrid` - Combined approach

  ## Extracted Attributes

  - `temporal_type` - Type of temporal expression (`:date`, `:duration`, `:relative`, `:time`)
  - `value` - Extracted value (string for dates, integer for durations)
  - `unit` - Unit for durations (days, weeks, months, years)
  - `reference` - Reference point for relative expressions

  ## Pattern Types

  The extractor recognizes several patterns:

  1. **US dates**: "1/15/2026", "01/15/2026"
  2. **ISO dates**: "2026-01-15"
  3. **Durations**: "for 7 days", "2 weeks", "3 months"
  4. **Relative**: "yesterday", "last week", "next month"
  5. **Times**: "8:00 AM", "14:30"

  ## Examples

      iex> context = %{text: "Started on 1/15/2026", method: :rule_based, opts: []}
      iex> {:ok, entities} = ClinicalNerEx.Extractors.Temporal.extract(context)
      iex> length(entities) >= 1
      true

      iex> context = %{text: "Continue for 2 weeks", method: :rule_based, opts: []}
      iex> {:ok, entities} = ClinicalNerEx.Extractors.Temporal.extract(context)
      iex> length(entities) >= 1
      true
  """

  @behaviour ClinicalNerEx.Extractors.Behaviour

  alias ClinicalNerEx.Entity

  # Date patterns
  @us_date_pattern ~r/\b(?<month>\d{1,2})\/(?<day>\d{1,2})\/(?<year>\d{2,4})\b/
  @iso_date_pattern ~r/\b(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})\b/

  # Duration patterns
  @duration_pattern ~r/(?:for\s+)?(?<value>\d+)\s*(?<unit>days?|weeks?|months?|years?)/i
  @duration_range_pattern ~r/(?<value1>\d+)\s*-\s*(?<value2>\d+)\s*(?<unit>days?|weeks?|months?|years?)/i

  # Relative patterns (defined as strings to avoid compilation issues)
  @relative_pattern_specs [
    {"yesterday", "yesterday", -1, "days"},
    {"today", "today", 0, "days"},
    {"tomorrow", "tomorrow", 1, "days"},
    {"last week", "last week", -1, "weeks"},
    {"next week", "next week", 1, "weeks"},
    {"last month", "last month", -1, "months"},
    {"next month", "next month", 1, "months"},
    {"last year", "last year", -1, "years"},
    {"next year", "next year", 1, "years"}
  ]

  # Time patterns
  @time_12h_pattern ~r/\b(?<hour>\d{1,2}):(?<minute>\d{2})\s*(?<period>AM|PM|am|pm)\b/
  @time_24h_pattern ~r/\b(?<hour>\d{2}):(?<minute>\d{2})(?::(?<second>\d{2}))?\b/

  @impl true
  @doc """
  Returns the entity type handled by this extractor.
  """
  @spec entity_type() :: :temporal
  def entity_type, do: :temporal

  @impl true
  @doc """
  Returns the extraction methods supported by this extractor.
  """
  @spec supported_methods() :: [:rule_based | :transformer | :hybrid]
  def supported_methods, do: [:rule_based, :transformer, :hybrid]

  @impl true
  @doc """
  Extract temporal entities from the context.

  The context must contain:
  - `text` - The clinical text to extract from
  - `method` - The extraction method
  - `opts` - Additional options (optional)

  ## Returns

  - `{:ok, [Entity.t()]}` - List of extracted temporal entities
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
  Extract temporal expressions using rule-based patterns.
  """
  @spec extract_rule_based(map()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract_rule_based(%{text: text}) do
    entities =
      []
      |> Kernel.++(extract_us_dates(text))
      |> Kernel.++(extract_iso_dates(text))
      |> Kernel.++(extract_durations(text))
      |> Kernel.++(extract_duration_ranges(text))
      |> Kernel.++(extract_relative(text))
      |> Kernel.++(extract_times(text))
      |> remove_overlapping()

    {:ok, entities}
  rescue
    e -> {:error, {:extraction_failed, Exception.message(e)}}
  end

  @doc """
  Extract temporal expressions using transformer model.

  Note: This is a stub. Full implementation requires Bumblebee integration.
  """
  @spec extract_transformer(map()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract_transformer(%{text: _text}) do
    # TODO: Implement with Bumblebee
    {:ok, []}
  end

  @doc """
  Extract temporal expressions using hybrid approach.
  """
  @spec extract_hybrid(map()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract_hybrid(context) do
    # For now, just use rule_based since transformer is a stub
    extract_rule_based(context)
  end

  # Private extraction functions

  defp extract_us_dates(text) do
    Regex.scan(@us_date_pattern, text, return: :index)
    |> Enum.map(fn [{start, length} | _] ->
      match_text = String.slice(text, start, length)

      Entity.new(%{
        type: :temporal,
        text: match_text,
        start_offset: start,
        end_offset: start + length,
        confidence: 0.95,
        attributes: %{
          temporal_type: :date,
          value: match_text,
          format: :us
        },
        extraction_method: :rule_based
      })
    end)
  end

  defp extract_iso_dates(text) do
    Regex.scan(@iso_date_pattern, text, return: :index)
    |> Enum.map(fn [{start, length} | _] ->
      match_text = String.slice(text, start, length)

      Entity.new(%{
        type: :temporal,
        text: match_text,
        start_offset: start,
        end_offset: start + length,
        confidence: 0.98,
        attributes: %{
          temporal_type: :date,
          value: match_text,
          format: :iso
        },
        extraction_method: :rule_based
      })
    end)
  end

  defp extract_durations(text) do
    Regex.scan(@duration_pattern, text, return: :index)
    |> Enum.map(fn [{start, length} | _] ->
      match_text = String.slice(text, start, length)
      captures = Regex.named_captures(@duration_pattern, match_text)

      Entity.new(%{
        type: :temporal,
        text: match_text,
        start_offset: start,
        end_offset: start + length,
        confidence: 0.90,
        attributes: %{
          temporal_type: :duration,
          value: parse_integer(captures["value"]),
          unit: normalize_unit(captures["unit"])
        },
        extraction_method: :rule_based
      })
    end)
  end

  defp extract_duration_ranges(text) do
    Regex.scan(@duration_range_pattern, text, return: :index)
    |> Enum.map(fn [{start, length} | _] ->
      match_text = String.slice(text, start, length)
      captures = Regex.named_captures(@duration_range_pattern, match_text)

      Entity.new(%{
        type: :temporal,
        text: match_text,
        start_offset: start,
        end_offset: start + length,
        confidence: 0.88,
        attributes: %{
          temporal_type: :duration_range,
          value_min: parse_integer(captures["value1"]),
          value_max: parse_integer(captures["value2"]),
          unit: normalize_unit(captures["unit"])
        },
        extraction_method: :rule_based
      })
    end)
  end

  defp extract_relative(text) do
    @relative_pattern_specs
    |> Enum.flat_map(fn {pattern_str, display, offset, unit} ->
      # Build regex from string at runtime
      pattern = ~r/\b#{Regex.escape(pattern_str)}\b/i

      Regex.scan(pattern, text, return: :index)
      |> Enum.map(fn [{start, length}] ->
        match_text = String.slice(text, start, length)

        Entity.new(%{
          type: :temporal,
          text: match_text,
          start_offset: start,
          end_offset: start + length,
          confidence: 0.92,
          attributes: %{
            temporal_type: :relative,
            value: display,
            offset: offset,
            unit: unit
          },
          extraction_method: :rule_based
        })
      end)
    end)
  end

  defp extract_times(text) do
    times_12h = extract_12h_times(text)
    times_24h = extract_24h_times(text)
    times_12h ++ times_24h
  end

  defp extract_12h_times(text) do
    Regex.scan(@time_12h_pattern, text, return: :index)
    |> Enum.map(fn [{start, length} | _] ->
      match_text = String.slice(text, start, length)
      captures = Regex.named_captures(@time_12h_pattern, match_text)

      Entity.new(%{
        type: :temporal,
        text: match_text,
        start_offset: start,
        end_offset: start + length,
        confidence: 0.93,
        attributes: %{
          temporal_type: :time,
          hour: parse_integer(captures["hour"]),
          minute: parse_integer(captures["minute"]),
          period: String.upcase(captures["period"]),
          format: :"12h"
        },
        extraction_method: :rule_based
      })
    end)
  end

  defp extract_24h_times(text) do
    Regex.scan(@time_24h_pattern, text, return: :index)
    |> Enum.map(fn [{start, length} | _] ->
      match_text = String.slice(text, start, length)
      captures = Regex.named_captures(@time_24h_pattern, match_text)

      # Filter out potential date fragments (e.g., "2026-01" matching as time)
      hour = parse_integer(captures["hour"])

      if hour <= 23 do
        Entity.new(%{
          type: :temporal,
          text: match_text,
          start_offset: start,
          end_offset: start + length,
          confidence: 0.91,
          attributes: %{
            temporal_type: :time,
            hour: hour,
            minute: parse_integer(captures["minute"]),
            second: parse_integer(captures["second"]),
            format: :"24h"
          },
          extraction_method: :rule_based
        })
      else
        nil
      end
    end)
    |> Enum.filter(& &1)
  end

  # Helper functions

  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil

  defp parse_integer(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp normalize_unit(unit) when is_binary(unit) do
    unit
    |> String.downcase()
    |> String.replace(~r/s$/, "")
    |> then(fn
      "day" -> "days"
      "week" -> "weeks"
      "month" -> "months"
      "year" -> "years"
      other -> other
    end)
  end

  defp normalize_unit(_), do: nil

  defp remove_overlapping(entities) do
    # Remove entities that are completely contained within larger entities
    entities
    |> Enum.sort_by(&{&1.start_offset, -(&1.end_offset - &1.start_offset)})
    |> Enum.reduce([], fn entity, acc ->
      if Enum.any?(acc, fn e -> Entity.contains?(e, entity) end) do
        acc
      else
        [entity | acc]
      end
    end)
    |> Enum.reverse()
  end
end
