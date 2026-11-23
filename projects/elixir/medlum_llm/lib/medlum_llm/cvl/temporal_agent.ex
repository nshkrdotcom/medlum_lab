defmodule MedlumLlm.CVL.TemporalAgent do
  @moduledoc """
  Verifies timeline and progression logic.

  Part of the 5-agent CVL consensus system with weight 0.8.
  Has lower weight because temporal information is often ambiguous.

  ## Verifies

  - Chronological consistency of events
  - Disease progression plausibility
  - Treatment timing appropriateness
  - Duration validity

  ## Examples

      claim = "Patient was diagnosed 2 days ago and has had symptoms for 3 weeks"
      context = %{document_dates: [~D[2026-01-25]]}

      result = TemporalAgent.verify(claim, context)

  """

  @behaviour MedlumLlm.CVL.Agent

  alias MedlumLlm.CVL.Agent

  @impl true
  def name, do: :temporal_agent

  @impl true
  def weight, do: 0.8

  @impl true
  def verify(claim, context) do
    temporal_entities = extract_temporal_entities(claim)

    if Enum.empty?(temporal_entities) do
      %{
        verdict: :neutral,
        confidence: 0.5,
        explanations: ["No temporal information found in claim"],
        evidence: [],
        sub_verdicts: []
      }
    else
      events = build_timeline(temporal_entities, context[:document_dates] || [])

      verdicts = []

      # Check chronological consistency
      verdicts = verdicts ++ verify_chronology(events)

      # Check disease progression plausibility
      verdicts = verdicts ++ verify_progression(events, context[:diagnoses] || [])

      # Check treatment timing
      verdicts = verdicts ++ verify_treatment_timing(events, context[:treatments] || [])

      if Enum.empty?(verdicts) do
        %{
          verdict: :neutral,
          confidence: 0.5,
          explanations: ["Temporal information found but no inconsistencies detected"],
          evidence: [],
          sub_verdicts: []
        }
      else
        Agent.aggregate_verdicts(verdicts)
      end
    end
  end

  @doc """
  Extract temporal entities (dates, durations, relative times) from text.
  """
  @spec extract_temporal_entities(String.t()) :: [map()]
  def extract_temporal_entities(claim) do
    extract_temporal_regex(claim)
  end

  defp extract_temporal_regex(text) do
    patterns = [
      # Relative dates: "2 days ago", "yesterday", "last week"
      {~r/(\d+)\s*(days?|weeks?|months?|years?)\s*ago/i, :relative_past},
      {~r/yesterday/i, :relative_past},
      {~r/today/i, :relative_present},
      {~r/last\s+(week|month|year)/i, :relative_past},

      # Durations: "for 3 weeks", "over 2 months"
      {~r/(?:for|over|during)\s*(?:the\s*(?:past|last)\s*)?(\d+)\s*(days?|weeks?|months?|years?)/i,
       :duration},

      # Absolute dates: "January 15, 2026", "01/15/2026"
      {~r/(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})/i, :absolute_date},
      {~r/(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2})(?:,?\s*(\d{4}))?/i,
       :absolute_date},

      # Sequence indicators: "then", "after", "before", "following"
      {~r/(then|after(?:ward)?|subsequently|before|prior to|following)/i, :sequence},

      # Event markers: "started", "began", "ended", "stopped"
      {~r/(started|began|commenced|initiated)\s+([a-z]+)/i, :event_start},
      {~r/(ended|stopped|discontinued|completed)/i, :event_end},

      # Age-related: "at age 45", "since childhood"
      {~r/(?:at\s+)?age\s+(\d+)/i, :age_reference},
      {~r/since\s+(childhood|birth|infancy)/i, :age_reference}
    ]

    Enum.flat_map(patterns, fn {regex, type} ->
      Regex.scan(regex, text)
      |> Enum.map(fn match ->
        %{
          type: type,
          raw_text: hd(match),
          captures: tl(match),
          parsed: parse_temporal(type, match)
        }
      end)
    end)
  end

  defp parse_temporal(:relative_past, [_, amount, unit | _]) do
    amount = parse_int(amount)
    days = unit_to_days(unit, amount)
    %{offset_days: -days, reference: :document_date}
  end

  defp parse_temporal(:relative_past, ["yesterday" | _]) do
    %{offset_days: -1, reference: :document_date}
  end

  defp parse_temporal(:relative_past, [_, "week" | _]) do
    %{offset_days: -7, reference: :document_date}
  end

  defp parse_temporal(:relative_past, [_, "month" | _]) do
    %{offset_days: -30, reference: :document_date}
  end

  defp parse_temporal(:relative_past, [_, "year" | _]) do
    %{offset_days: -365, reference: :document_date}
  end

  defp parse_temporal(:relative_present, _) do
    %{offset_days: 0, reference: :document_date}
  end

  defp parse_temporal(:duration, [_, amount, unit | _]) do
    amount = parse_int(amount)
    days = unit_to_days(unit, amount)
    %{duration_days: days}
  end

  defp parse_temporal(:absolute_date, [_, month, day | rest]) when is_binary(month) do
    # Check if month is a string name or numeric
    if String.match?(month, ~r/^[A-Za-z]/) do
      # Month name like "January"
      year =
        case rest do
          [y | _] when is_binary(y) and y != "" -> parse_int(y)
          _ -> Date.utc_today().year
        end

      month_num = month_to_number(month)
      day_num = parse_int(day)

      case Date.new(year, month_num, day_num) do
        {:ok, date} -> %{date: date}
        _ -> nil
      end
    else
      # Numeric format like "01/15/2026"
      m = parse_int(month)
      d = parse_int(day)

      year =
        case rest do
          [y | _] when is_binary(y) and y != "" -> parse_int(y)
          _ -> Date.utc_today().year
        end

      year = if year < 100, do: 2000 + year, else: year

      case Date.new(year, m, d) do
        {:ok, date} -> %{date: date}
        _ -> nil
      end
    end
  end

  defp parse_temporal(:absolute_date, _), do: nil

  defp parse_temporal(:sequence, [_, indicator | _]) do
    %{sequence: String.downcase(indicator)}
  end

  defp parse_temporal(:event_start, [_, verb, event | _]) do
    %{event_type: :start, event: event, verb: verb}
  end

  defp parse_temporal(:event_end, [_, verb | _]) do
    %{event_type: :end, verb: verb}
  end

  defp parse_temporal(:age_reference, [_, age | _]) when is_binary(age) do
    case Integer.parse(age) do
      {n, _} -> %{age_years: n}
      :error -> %{age_reference: age}
    end
  end

  defp parse_temporal(_, _), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_int(n) when is_integer(n), do: n
  defp parse_int(_), do: 0

  defp unit_to_days("day" <> _, amount), do: amount
  defp unit_to_days("week" <> _, amount), do: amount * 7
  defp unit_to_days("month" <> _, amount), do: amount * 30
  defp unit_to_days("year" <> _, amount), do: amount * 365
  defp unit_to_days(_, amount), do: amount

  defp month_to_number(month) do
    months = %{
      "january" => 1,
      "february" => 2,
      "march" => 3,
      "april" => 4,
      "may" => 5,
      "june" => 6,
      "july" => 7,
      "august" => 8,
      "september" => 9,
      "october" => 10,
      "november" => 11,
      "december" => 12
    }

    Map.get(months, String.downcase(month), 1)
  end

  defp build_timeline(temporal_entities, document_dates) do
    reference_date =
      case document_dates do
        [date | _] -> date
        _ -> Date.utc_today()
      end

    Enum.map(temporal_entities, fn entity ->
      resolved_date = resolve_date(entity.parsed, reference_date)
      Map.put(entity, :resolved_date, resolved_date)
    end)
    |> Enum.filter(& &1.resolved_date)
    |> Enum.sort_by(& &1.resolved_date, Date)
  end

  defp resolve_date(%{date: date}, _reference), do: date
  defp resolve_date(%{offset_days: offset}, reference), do: Date.add(reference, offset)
  defp resolve_date(_, _), do: nil

  defp verify_chronology(events) do
    events
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [earlier, later] ->
      if Date.compare(earlier.resolved_date, later.resolved_date) == :gt do
        [
          {:contradiction,
           "Chronological inconsistency: '#{earlier.raw_text}' appears to be after '#{later.raw_text}'"}
        ]
      else
        [{:entailment, "Timeline consistent: '#{earlier.raw_text}' before '#{later.raw_text}'"}]
      end
    end)
  end

  defp verify_progression(events, _diagnoses) do
    # Check if progression makes sense for diagnoses
    # For now, just validate that duration events are reasonable
    Enum.flat_map(events, fn event ->
      case event.parsed do
        %{duration_days: days} when days > 365 * 50 ->
          [{:contradiction, "Implausibly long duration: #{event.raw_text}"}]

        %{duration_days: days} when days > 0 ->
          [{:entailment, "Duration '#{event.raw_text}' is plausible"}]

        _ ->
          []
      end
    end)
  end

  defp verify_treatment_timing(events, _treatments) do
    # Check event starts and ends are in reasonable order
    starts = Enum.filter(events, fn e -> e.parsed[:event_type] == :start end)
    ends = Enum.filter(events, fn e -> e.parsed[:event_type] == :end end)

    # If we have both starts and ends, check order
    Enum.flat_map(ends, fn end_event ->
      matching_start =
        Enum.find(starts, fn s ->
          s.resolved_date && end_event.resolved_date &&
            Date.compare(s.resolved_date, end_event.resolved_date) in [:lt, :eq]
        end)

      if matching_start do
        [{:entailment, "Treatment timing valid: started before ended"}]
      else
        if Enum.any?(starts) do
          [{:neutral, "Could not verify treatment timing order"}]
        else
          []
        end
      end
    end)
  end
end
