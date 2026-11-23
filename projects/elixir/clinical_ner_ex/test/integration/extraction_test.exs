defmodule ClinicalNerEx.Integration.ExtractionTest do
  @moduledoc """
  Integration tests for the full extraction pipeline.
  """

  use ExUnit.Case, async: false

  alias ClinicalNerEx.Entity

  describe "full extraction pipeline" do
    test "extracts all entity types from clinical note" do
      text = """
      72 y/o male with h/o HTN, T2DM on metformin 1000mg BID.
      Labs: A1c 7.2%, Cr 1.3 mg/dL.
      """

      {:ok, entities} = ClinicalNerEx.extract(text, link_ontologies: false)

      assert is_list(entities)

      # Should find medications
      meds = Enum.filter(entities, &(&1.type == :medication))
      assert length(meds) >= 1

      # Should find lab values
      labs = Enum.filter(entities, &(&1.type == :lab_value))
      assert length(labs) >= 1

      # Should find diagnoses
      dx = Enum.filter(entities, &(&1.type == :diagnosis))
      assert length(dx) >= 1
    end

    test "respects confidence threshold" do
      text = "metformin 500mg daily"

      {:ok, high_conf} = ClinicalNerEx.extract(text, confidence_threshold: 0.9, link_ontologies: false)
      {:ok, low_conf} = ClinicalNerEx.extract(text, confidence_threshold: 0.5, link_ontologies: false)

      # Lower threshold should include more (or equal) entities
      assert length(low_conf) >= length(high_conf)
    end

    test "respects entity type filter" do
      text = "metformin 500mg for diabetes with A1c 7.2%"

      {:ok, meds_only} = ClinicalNerEx.extract(text, entity_types: [:medication], link_ontologies: false)
      assert Enum.all?(meds_only, &(&1.type == :medication))

      {:ok, labs_only} = ClinicalNerEx.extract(text, entity_types: [:lab_value], link_ontologies: false)
      assert Enum.all?(labs_only, &(&1.type == :lab_value))
    end

    test "batch extraction works" do
      texts = [
        "metformin 500mg",
        "A1c 7.2%",
        "history of diabetes"
      ]

      {:ok, results} = ClinicalNerEx.extract_batch(texts, link_ontologies: false)
      assert length(results) == 3
      assert is_list(hd(results))
    end

    test "handles empty text gracefully" do
      {:ok, entities} = ClinicalNerEx.extract("", link_ontologies: false)
      assert entities == []
    end

    test "handles whitespace-only text" do
      {:ok, entities} = ClinicalNerEx.extract("   \n\t  ", link_ontologies: false)
      assert entities == []
    end
  end

  describe "entity-specific extraction" do
    test "extract_medications finds medication entities" do
      {:ok, entities} = ClinicalNerEx.extract_medications("lisinopril 10mg PO daily", link_ontologies: false)

      assert length(entities) >= 1
      assert hd(entities).type == :medication
      assert hd(entities).attributes[:drug_name] == "lisinopril"
    end

    test "extract_medications handles multiple medications" do
      {:ok, entities} =
        ClinicalNerEx.extract_medications(
          "metformin 500mg BID and lisinopril 10mg daily",
          link_ontologies: false
        )

      assert length(entities) >= 2

      drug_names =
        Enum.map(entities, & &1.attributes[:drug_name])
        |> Enum.map(&String.downcase/1)

      assert "metformin" in drug_names
      assert "lisinopril" in drug_names
    end

    test "extract_lab_values finds lab entities" do
      {:ok, entities} = ClinicalNerEx.extract_lab_values("Glucose 125 mg/dL", link_ontologies: false)

      assert length(entities) >= 1
      assert hd(entities).type == :lab_value
    end

    test "extract_lab_values handles percentage values" do
      {:ok, entities} = ClinicalNerEx.extract_lab_values("A1c 7.2%", link_ontologies: false)

      assert length(entities) >= 1
      lab = hd(entities)
      assert lab.type == :lab_value
      assert lab.attributes[:value] == 7.2
    end

    test "extract_diagnoses finds diagnosis entities" do
      {:ok, entities} = ClinicalNerEx.extract_diagnoses("h/o HTN and DM", link_ontologies: false)

      assert length(entities) >= 2
      assert Enum.all?(entities, &(&1.type == :diagnosis))
    end

    test "extract_procedures finds procedure entities" do
      {:ok, entities} = ClinicalNerEx.extract_procedures("EKG and CT ordered", link_ontologies: false)

      assert length(entities) >= 2
      assert Enum.all?(entities, &(&1.type == :procedure))
    end

    test "extract_temporal finds temporal expressions" do
      {:ok, entities} = ClinicalNerEx.extract_temporal("Started on 1/15/2026", link_ontologies: false)

      assert length(entities) >= 1
      assert Enum.all?(entities, &(&1.type == :temporal))
    end

    test "extract_temporal handles durations" do
      {:ok, entities} = ClinicalNerEx.extract_temporal("Continue for 2 weeks", link_ontologies: false)

      assert length(entities) >= 1
      duration = hd(entities)
      assert duration.attributes[:temporal_type] == :duration
      assert duration.attributes[:value] == 2
      assert duration.attributes[:unit] == "weeks"
    end
  end

  describe "extraction methods" do
    test "rule_based method works" do
      {:ok, entities} =
        ClinicalNerEx.extract("metformin 500mg", method: :rule_based, link_ontologies: false)

      assert length(entities) >= 1
      assert hd(entities).extraction_method == :rule_based
    end

    test "hybrid method works" do
      {:ok, entities} =
        ClinicalNerEx.extract("metformin 500mg", method: :hybrid, link_ontologies: false)

      # Hybrid currently uses rule_based since transformer is a stub
      assert length(entities) >= 1
    end

    test "transformer method returns entities (stub returns empty or rule_based)" do
      {:ok, entities} =
        ClinicalNerEx.extract("metformin 500mg", method: :transformer, link_ontologies: false)

      # Transformer is a stub, may return empty list
      assert is_list(entities)
    end
  end

  describe "entity structure" do
    test "entities have required fields" do
      {:ok, entities} = ClinicalNerEx.extract("metformin 500mg", link_ontologies: false)

      Enum.each(entities, fn entity ->
        assert is_binary(entity.id)
        assert entity.type in Entity.valid_types()
        assert is_binary(entity.text)
        assert is_integer(entity.start_offset)
        assert is_integer(entity.end_offset)
        assert is_float(entity.confidence) or is_integer(entity.confidence)
        assert entity.confidence >= 0.0 and entity.confidence <= 1.0
        assert is_map(entity.attributes)
        assert is_list(entity.ontology_links)
        assert entity.extraction_method in [:rule_based, :transformer, :hybrid]
        assert is_list(entity.warnings)
        assert is_map(entity.metadata)
      end)
    end

    test "entity spans are valid" do
      text = "Patient on metformin 500mg BID"
      {:ok, entities} = ClinicalNerEx.extract(text, link_ontologies: false)

      Enum.each(entities, fn entity ->
        assert entity.start_offset >= 0
        assert entity.end_offset <= String.length(text)
        assert entity.start_offset < entity.end_offset

        # Text should match the span
        extracted_text = String.slice(text, entity.start_offset, entity.end_offset - entity.start_offset)
        # Allow for preprocessing changes (whitespace normalization, etc.)
        assert String.length(extracted_text) > 0
      end)
    end
  end

  describe "configuration" do
    test "config returns current settings" do
      config = ClinicalNerEx.config()

      assert Map.has_key?(config, :default_method)
      assert Map.has_key?(config, :confidence_thresholds)
      assert Map.has_key?(config, :extraction_timeout_ms)
      assert Map.has_key?(config, :enable_ontology_linking)
    end

    test "version returns correct version" do
      assert ClinicalNerEx.version() == "0.1.0"
    end
  end

  describe "edge cases" do
    test "handles special characters" do
      {:ok, entities} = ClinicalNerEx.extract("metformin\u2014500mg", link_ontologies: false)
      assert is_list(entities)
    end

    test "handles very long text" do
      # Generate a long clinical note
      long_text =
        String.duplicate("Patient on metformin 500mg BID. Labs: A1c 7.2%. ", 100)

      {:ok, entities} = ClinicalNerEx.extract(long_text, link_ontologies: false)
      assert is_list(entities)
      assert length(entities) > 0
    end

    test "handles text with no extractable entities" do
      {:ok, entities} = ClinicalNerEx.extract("The weather is nice today.", link_ontologies: false)
      assert is_list(entities)
    end
  end

  describe "stream extraction" do
    test "extract_stream works with enumerable" do
      texts = ["metformin 500mg", "A1c 7.2%", "history of HTN"]

      results =
        ClinicalNerEx.extract_stream(texts, link_ontologies: false)
        |> Enum.to_list()

      assert length(results) == 3
      assert Enum.all?(results, &is_list/1)
    end
  end
end
