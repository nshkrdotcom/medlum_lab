defmodule ClinicalNerExTest do
  use ExUnit.Case
  doctest ClinicalNerEx

  describe "extract/2" do
    test "returns ok tuple with empty list for stub" do
      {:ok, entities} = ClinicalNerEx.extract("Patient on metformin 500mg BID")
      assert is_list(entities)
    end

    test "accepts options" do
      {:ok, entities} =
        ClinicalNerEx.extract("test",
          method: :rule_based,
          entity_types: [:medication],
          confidence_threshold: 0.8
        )

      assert is_list(entities)
    end
  end

  describe "extract_medications/2" do
    test "returns ok tuple" do
      {:ok, meds} = ClinicalNerEx.extract_medications("lisinopril 10mg PO daily")
      assert is_list(meds)
    end
  end

  describe "extract_lab_values/2" do
    test "returns ok tuple" do
      {:ok, labs} = ClinicalNerEx.extract_lab_values("A1c 6.5%")
      assert is_list(labs)
    end
  end

  describe "extract_diagnoses/2" do
    test "returns ok tuple" do
      {:ok, diagnoses} = ClinicalNerEx.extract_diagnoses("Type 2 diabetes")
      assert is_list(diagnoses)
    end
  end

  describe "extract_procedures/2" do
    test "returns ok tuple" do
      {:ok, procedures} = ClinicalNerEx.extract_procedures("colonoscopy")
      assert is_list(procedures)
    end
  end

  describe "extract_temporal/2" do
    test "returns ok tuple" do
      {:ok, temporal} = ClinicalNerEx.extract_temporal("January 15, 2026")
      assert is_list(temporal)
    end
  end

  describe "extract_batch/2" do
    test "processes multiple texts" do
      texts = ["Patient on aspirin", "Labs show A1c 6.5%", "History of COPD"]
      {:ok, results} = ClinicalNerEx.extract_batch(texts)

      assert length(results) == 3
      assert Enum.all?(results, &is_list/1)
    end

    test "handles empty list" do
      {:ok, results} = ClinicalNerEx.extract_batch([])
      assert results == []
    end
  end

  describe "extract_stream/2" do
    test "returns an enumerable" do
      texts = ["test1", "test2"]
      stream = ClinicalNerEx.extract_stream(texts)
      # Stream structs implement Enumerable
      assert Enumerable.impl_for(stream) != nil
    end

    test "stream can be enumerated" do
      texts = ["Patient on aspirin", "Labs show A1c"]
      results = ClinicalNerEx.extract_stream(texts) |> Enum.to_list()
      assert length(results) == 2
    end
  end

  describe "config/0" do
    test "returns configuration map" do
      config = ClinicalNerEx.config()

      assert is_map(config)
      assert Map.has_key?(config, :default_method)
      assert Map.has_key?(config, :confidence_thresholds)
      assert Map.has_key?(config, :extraction_timeout_ms)
      assert Map.has_key?(config, :enable_ontology_linking)
    end
  end

  describe "version/0" do
    test "returns version string" do
      version = ClinicalNerEx.version()
      assert version == "0.1.0"
    end
  end
end
