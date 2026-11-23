defmodule MedlumLlm.CVL.TemporalAgentTest do
  use ExUnit.Case

  alias MedlumLlm.CVL.TemporalAgent

  describe "name/0 and weight/0" do
    test "returns correct values" do
      assert TemporalAgent.name() == :temporal_agent
      assert TemporalAgent.weight() == 0.8
    end
  end

  describe "extract_temporal_entities/1" do
    test "extracts relative dates" do
      entities = TemporalAgent.extract_temporal_entities("Started 2 days ago")

      assert length(entities) >= 1
      assert Enum.any?(entities, &(&1.type == :relative_past))
    end

    test "extracts durations" do
      entities = TemporalAgent.extract_temporal_entities("Symptoms for 3 weeks")

      assert length(entities) >= 1
      duration = Enum.find(entities, &(&1.type == :duration))
      assert duration != nil
      assert duration.parsed.duration_days == 21
    end

    test "extracts absolute dates" do
      entities = TemporalAgent.extract_temporal_entities("Seen on January 15, 2026")

      assert length(entities) >= 1
    end

    test "extracts sequence indicators" do
      entities = TemporalAgent.extract_temporal_entities("Then developed fever")

      assert Enum.any?(entities, &(&1.type == :sequence))
    end

    test "extracts yesterday" do
      entities = TemporalAgent.extract_temporal_entities("Yesterday the patient complained of pain")

      assert Enum.any?(entities, &(&1.type == :relative_past))
      yesterday = Enum.find(entities, &(&1.raw_text == "yesterday"))
      assert yesterday.parsed.offset_days == -1
    end

    test "extracts today" do
      entities = TemporalAgent.extract_temporal_entities("Today patient feels better")

      assert Enum.any?(entities, &(&1.type == :relative_present))
      today = Enum.find(entities, &(&1.type == :relative_present))
      assert today.parsed.offset_days == 0
    end

    test "extracts last week/month/year" do
      entities = TemporalAgent.extract_temporal_entities("Started last week")
      assert Enum.any?(entities, fn e -> e.type == :relative_past end)

      entities = TemporalAgent.extract_temporal_entities("Diagnosed last month")
      assert Enum.any?(entities, fn e -> e.type == :relative_past end)

      entities = TemporalAgent.extract_temporal_entities("Surgery last year")
      assert Enum.any?(entities, fn e -> e.type == :relative_past end)
    end

    test "extracts event start markers" do
      entities = TemporalAgent.extract_temporal_entities("Started medication")

      assert Enum.any?(entities, &(&1.type == :event_start))
    end

    test "extracts event end markers" do
      entities = TemporalAgent.extract_temporal_entities("Treatment ended")

      assert Enum.any?(entities, &(&1.type == :event_end))
    end

    test "extracts age references" do
      entities = TemporalAgent.extract_temporal_entities("At age 45 was diagnosed")

      assert Enum.any?(entities, &(&1.type == :age_reference))
      age = Enum.find(entities, &(&1.type == :age_reference))
      assert age.parsed.age_years == 45
    end

    test "extracts since childhood references" do
      entities = TemporalAgent.extract_temporal_entities("Has had asthma since childhood")

      assert Enum.any?(entities, &(&1.type == :age_reference))
    end

    test "extracts numeric date format" do
      entities = TemporalAgent.extract_temporal_entities("Seen on 01/15/2026")

      assert length(entities) >= 1
      date_entity = Enum.find(entities, &(&1.type == :absolute_date))
      assert date_entity != nil
      assert date_entity.parsed.date == ~D[2026-01-15]
    end

    test "extracts multiple temporal entities" do
      claim = "Patient diagnosed 2 days ago, symptoms for 3 weeks, started treatment yesterday"
      entities = TemporalAgent.extract_temporal_entities(claim)

      # Should find multiple temporal references
      assert length(entities) >= 3
    end
  end

  describe "verify/2" do
    test "verifies consistent timeline" do
      claim = "Patient had symptoms for 2 weeks before diagnosis 3 days ago"
      context = %{document_dates: [~D[2026-01-25]]}

      result = TemporalAgent.verify(claim, context)

      # Should find temporal info but no contradictions
      assert result.verdict in [:entailment, :neutral]
    end

    test "returns neutral for no temporal info" do
      claim = "Patient has chest pain"
      context = %{}

      result = TemporalAgent.verify(claim, context)

      assert result.verdict == :neutral
    end

    test "flags implausibly long duration" do
      claim = "Symptoms for 100 years"
      context = %{}

      result = TemporalAgent.verify(claim, context)

      assert result.verdict == :contradiction
    end

    test "validates reasonable duration" do
      claim = "Symptoms for 2 weeks"
      context = %{}

      result = TemporalAgent.verify(claim, context)

      assert result.verdict == :entailment
    end

    test "validates duration in days" do
      claim = "Pain for 5 days"
      context = %{}

      result = TemporalAgent.verify(claim, context)

      assert result.verdict == :entailment
      assert Enum.any?(result.explanations, &String.contains?(&1, "plausible"))
    end

    test "validates duration in months" do
      claim = "Treatment for 6 months"
      context = %{}

      result = TemporalAgent.verify(claim, context)

      assert result.verdict == :entailment
    end

    test "uses document date as reference" do
      claim = "Diagnosed 3 days ago"
      context = %{document_dates: [~D[2026-01-25]]}

      result = TemporalAgent.verify(claim, context)

      # With a document date, it should be able to resolve the relative date
      assert result.verdict in [:entailment, :neutral]
    end

    test "handles missing document dates" do
      claim = "Diagnosed 3 days ago"
      context = %{}

      result = TemporalAgent.verify(claim, context)

      # Should still process, using today as reference
      assert result.verdict in [:entailment, :neutral]
    end

    test "returns proper result structure" do
      claim = "Patient symptoms for 2 weeks"
      context = %{}

      result = TemporalAgent.verify(claim, context)

      assert is_atom(result.verdict)
      assert is_float(result.confidence)
      assert is_list(result.explanations)
      assert is_list(result.evidence)
      assert is_list(result.sub_verdicts)
    end

    test "detects implausibly long year-based duration" do
      claim = "Has had symptoms for 200 years"
      context = %{}

      result = TemporalAgent.verify(claim, context)

      assert result.verdict == :contradiction
      assert Enum.any?(result.explanations, &String.contains?(&1, "Implausibly long"))
    end
  end

  describe "edge cases" do
    test "handles empty claim" do
      result = TemporalAgent.verify("", %{})

      assert result.verdict == :neutral
      assert Enum.any?(result.explanations, &String.contains?(&1, "No temporal information"))
    end

    test "handles claim with only sequence indicators" do
      result = TemporalAgent.verify("Then the patient felt better", %{})

      # Sequence indicators alone don't produce verdicts
      assert result.verdict == :neutral
    end

    test "handles multiple document dates - uses first" do
      claim = "Diagnosed 1 day ago"
      context = %{document_dates: [~D[2026-01-25], ~D[2026-01-20]]}

      result = TemporalAgent.verify(claim, context)

      # Should use first document date as reference
      assert result.verdict in [:entailment, :neutral]
    end
  end
end
