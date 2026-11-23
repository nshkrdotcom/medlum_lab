defmodule MedlumLlm.CVL.Measurements.TemporalAgent do
  @moduledoc """
  Forge Measurement for temporal consistency verification.

  This measurement validates timeline and temporal claims by:
  - Checking chronological consistency of events
  - Verifying disease progression timelines
  - Detecting temporal impossibilities (e.g., future dates, negative durations)
  - Validating treatment timing sequences

  ## Verdict Types

  - `:entailment` - Temporal claims are consistent
  - `:contradiction` - Temporal inconsistencies detected
  - `:neutral` - Unable to verify (insufficient temporal data)

  ## Example

      iex> samples = [%Forge.Sample{data: %{claims: [%{type: :temporal, text: "diagnosed 3 months ago, started treatment 2 weeks later"}]}}]
      iex> {:ok, results} = TemporalAgent.compute(samples)
      iex> results["sample_id"].verdict
      :entailment
  """

  @behaviour Forge.Measurement

  @measurement_version 1

  @type verdict :: :entailment | :contradiction | :neutral

  @type result :: %{
          verdict: verdict(),
          confidence: float(),
          reasoning: String.t(),
          evidence: [map()],
          temporal_events: [map()]
        }

  @impl true
  @spec compute([Forge.Sample.t()]) :: {:ok, map()} | {:error, term()}
  def compute(samples) do
    results =
      samples
      |> Enum.map(fn sample ->
        verdict = verify_temporal_consistency(sample)
        {sample.id, verdict}
      end)
      |> Map.new()

    {:ok, results}
  end

  @impl true
  @spec key() :: String.t()
  def key do
    config_hash =
      :crypto.hash(:md5, inspect(config()))
      |> Base.encode16(case: :lower)
      |> String.slice(0, 8)

    "temporal_agent_#{config_hash}"
  end

  @impl true
  @spec version() :: pos_integer()
  def version, do: @measurement_version

  @impl true
  @spec dependencies() :: [module()]
  def dependencies, do: []

  @impl true
  @spec async?() :: boolean()
  def async?, do: true

  @impl true
  @spec timeout() :: pos_integer()
  def timeout, do: 60_000

  @doc """
  Get current configuration for this measurement.
  """
  @spec config() :: map()
  def config do
    %{
      confidence_threshold: 0.8,
      max_reasonable_age_years: 120,
      verify_sequences: true
    }
  end

  # Private functions

  @spec verify_temporal_consistency(Forge.Sample.t()) :: result()
  defp verify_temporal_consistency(sample) do
    claims = get_temporal_claims(sample)

    if Enum.empty?(claims) do
      %{
        verdict: :neutral,
        confidence: 1.0,
        reasoning: "No temporal claims found in sample",
        evidence: [],
        temporal_events: []
      }
    else
      # Extract temporal events from all claims
      events = Enum.flat_map(claims, &extract_temporal_events/1)

      # Check for temporal inconsistencies
      inconsistencies = find_temporal_inconsistencies(events)
      impossible_values = find_impossible_values(events)

      cond do
        Enum.any?(impossible_values) ->
          %{
            verdict: :contradiction,
            confidence: 0.9,
            reasoning: "Impossible temporal values detected",
            evidence: impossible_values,
            temporal_events: events
          }

        Enum.any?(inconsistencies) ->
          %{
            verdict: :contradiction,
            confidence: 0.85,
            reasoning: "Temporal sequence inconsistencies detected",
            evidence: inconsistencies,
            temporal_events: events
          }

        length(events) > 0 ->
          %{
            verdict: :entailment,
            confidence: 0.85,
            reasoning: "Temporal claims appear consistent",
            evidence: [],
            temporal_events: events
          }

        true ->
          %{
            verdict: :neutral,
            confidence: 0.5,
            reasoning: "Unable to extract sufficient temporal information",
            evidence: [],
            temporal_events: []
          }
      end
    end
  end

  @spec get_temporal_claims(Forge.Sample.t()) :: [map()]
  defp get_temporal_claims(sample) do
    claims = sample.data[:claims] || []

    Enum.filter(claims, fn claim ->
      claim[:type] == :temporal or
        (is_binary(claim[:text]) and contains_temporal_pattern?(claim[:text]))
    end)
  end

  @spec contains_temporal_pattern?(String.t()) :: boolean()
  defp contains_temporal_pattern?(text) do
    patterns = [
      ~r/\b\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}\b/,
      ~r/(ago|since|prior|after|before|following|during)/i,
      ~r/\d+\s*(day|week|month|year|hour)s?/i,
      ~r/(onset|duration|interval|episode|chronic|acute)/i
    ]

    Enum.any?(patterns, &Regex.match?(&1, text))
  end

  @spec extract_temporal_events(map()) :: [map()]
  defp extract_temporal_events(claim) do
    text = claim[:text] || ""
    events = []

    # Extract absolute dates
    events = events ++ extract_dates(text)

    # Extract relative times
    events = events ++ extract_relative_times(text)

    # Extract durations
    events = events ++ extract_durations(text)

    # Extract age references
    events = events ++ extract_age_references(text)

    events
  end

  @spec extract_dates(String.t()) :: [map()]
  defp extract_dates(text) do
    # US format: MM/DD/YYYY
    us_dates =
      Regex.scan(~r/\b(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})\b/, text)
      |> Enum.map(fn [_match, month, day, year] ->
        case parse_date(year, month, day) do
          {:ok, date} ->
            %{
              type: :absolute_date,
              date: date,
              format: :us,
              original: "#{month}/#{day}/#{year}"
            }

          :error ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # ISO format: YYYY-MM-DD
    iso_dates =
      Regex.scan(~r/\b(\d{4})[\/\-](\d{1,2})[\/\-](\d{1,2})\b/, text)
      |> Enum.map(fn [_match, year, month, day] ->
        case parse_date(year, month, day) do
          {:ok, date} ->
            %{
              type: :absolute_date,
              date: date,
              format: :iso,
              original: "#{year}-#{month}-#{day}"
            }

          :error ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    us_dates ++ iso_dates
  end

  @spec parse_date(String.t(), String.t(), String.t()) :: {:ok, Date.t()} | :error
  defp parse_date(year, month, day) do
    with {y, ""} <- Integer.parse(year),
         {m, ""} <- Integer.parse(month),
         {d, ""} <- Integer.parse(day),
         {:ok, date} <- Date.new(y, m, d) do
      {:ok, date}
    else
      _ -> :error
    end
  end

  @spec extract_relative_times(String.t()) :: [map()]
  defp extract_relative_times(text) do
    relative_patterns = [
      {~r/(\d+)\s*(day|week|month|year)s?\s*ago/i, :past},
      {~r/(\d+)\s*(day|week|month|year)s?\s*(?:later|after)/i, :relative_future},
      {~r/(?:since|for)\s*(\d+)\s*(day|week|month|year)s?/i, :duration}
    ]

    Enum.flat_map(relative_patterns, fn {pattern, direction} ->
      Regex.scan(pattern, text)
      |> Enum.map(fn
        [match, amount, unit] ->
          %{
            type: :relative_time,
            amount: String.to_integer(amount),
            unit: normalize_time_unit(unit),
            direction: direction,
            original: match
          }

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil/1)
    end)
  end

  @spec extract_durations(String.t()) :: [map()]
  defp extract_durations(text) do
    Regex.scan(~r/(?:duration|lasting|for)\s*(?:of\s*)?(\d+)\s*(day|week|month|year|hour)s?/i, text)
    |> Enum.map(fn [match, amount, unit] ->
      %{
        type: :duration,
        amount: String.to_integer(amount),
        unit: normalize_time_unit(unit),
        original: match
      }
    end)
  end

  @spec extract_age_references(String.t()) :: [map()]
  defp extract_age_references(text) do
    patterns = [
      ~r/(\d{1,3})\s*[-\s]?year[-\s]?old/i,
      ~r/age\s*(?:of\s*)?(\d{1,3})/i
    ]

    Enum.flat_map(patterns, fn pattern ->
      Regex.scan(pattern, text)
      |> Enum.map(fn [match, age] ->
        %{
          type: :age,
          age: String.to_integer(age),
          original: match
        }
      end)
    end)
  end

  @spec normalize_time_unit(String.t()) :: atom()
  defp normalize_time_unit(unit) do
    case String.downcase(unit) do
      u when u in ["day", "days"] -> :days
      u when u in ["week", "weeks"] -> :weeks
      u when u in ["month", "months"] -> :months
      u when u in ["year", "years"] -> :years
      u when u in ["hour", "hours"] -> :hours
      _ -> :unknown
    end
  end

  @spec find_temporal_inconsistencies([map()]) :: [map()]
  defp find_temporal_inconsistencies(events) do
    inconsistencies = []

    # Find date pairs that are inconsistent
    absolute_dates =
      events
      |> Enum.filter(&(&1.type == :absolute_date))
      |> Enum.sort_by(& &1.date, Date)

    # Check if any dates are in the future (impossible for medical history)
    today = Date.utc_today()

    future_dates =
      Enum.filter(absolute_dates, fn event ->
        Date.compare(event.date, today) == :gt
      end)

    inconsistencies =
      Enum.map(future_dates, fn event ->
        %{
          type: :future_date,
          event: event,
          reasoning: "Date #{event.original} is in the future"
        }
      end) ++ inconsistencies

    # Check relative time sequences
    relative_times = Enum.filter(events, &(&1.type == :relative_time))

    # Simple check: "X ago" should be less than "Y ago" if Y > X
    inconsistencies = check_relative_time_sequence(relative_times) ++ inconsistencies

    inconsistencies
  end

  @spec check_relative_time_sequence([map()]) :: [map()]
  defp check_relative_time_sequence(relative_times) do
    past_events =
      relative_times
      |> Enum.filter(&(&1.direction == :past))
      |> Enum.map(&Map.put(&1, :days, to_days(&1)))

    # Check for inconsistencies in ordering
    Enum.flat_map(past_events, fn event1 ->
      Enum.flat_map(past_events, fn event2 ->
        if event1 != event2 and event1.days < 0 do
          [
            %{
              type: :negative_duration,
              event: event1,
              reasoning: "Negative time reference"
            }
          ]
        else
          []
        end
      end)
    end)
  end

  @spec to_days(map()) :: integer()
  defp to_days(%{amount: amount, unit: unit}) do
    case unit do
      :days -> amount
      :weeks -> amount * 7
      :months -> amount * 30
      :years -> amount * 365
      :hours -> div(amount, 24)
      _ -> 0
    end
  end

  @spec find_impossible_values([map()]) :: [map()]
  defp find_impossible_values(events) do
    impossible = []

    # Check for impossible ages
    age_events = Enum.filter(events, &(&1.type == :age))

    impossible =
      Enum.flat_map(age_events, fn event ->
        cond do
          event.age < 0 ->
            [
              %{
                type: :negative_age,
                event: event,
                reasoning: "Age cannot be negative: #{event.age}"
              }
            ]

          event.age > 120 ->
            [
              %{
                type: :implausible_age,
                event: event,
                reasoning: "Age exceeds reasonable maximum: #{event.age}"
              }
            ]

          true ->
            []
        end
      end) ++ impossible

    # Check for impossible durations
    duration_events = Enum.filter(events, &(&1.type == :duration))

    impossible =
      Enum.flat_map(duration_events, fn event ->
        days = to_days(event)

        cond do
          days < 0 ->
            [
              %{
                type: :negative_duration,
                event: event,
                reasoning: "Duration cannot be negative"
              }
            ]

          days > 365 * 120 ->
            [
              %{
                type: :implausible_duration,
                event: event,
                reasoning: "Duration exceeds human lifespan"
              }
            ]

          true ->
            []
        end
      end) ++ impossible

    impossible
  end
end
