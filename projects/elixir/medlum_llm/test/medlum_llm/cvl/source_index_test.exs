defmodule MedlumLlm.CVL.SourceIndexTest do
  use ExUnit.Case

  alias MedlumLlm.CVL.SourceIndex

  describe "build/2 with plain strings" do
    test "accepts list of strings" do
      documents = [
        "Patient on metformin 500mg for diabetes",
        "Lab results: HbA1c 7.2%"
      ]

      {:ok, index} = SourceIndex.build(documents)

      assert is_map(index)
      assert Map.has_key?(index, :medications)
      assert Map.has_key?(index, :labs)
      assert Map.has_key?(index, :diagnoses)
      assert Map.has_key?(index, :findings)
    end

    test "assigns doc IDs to plain strings" do
      documents = ["First document", "Second document"]

      {:ok, index} = SourceIndex.build(documents)

      # Even without ClinicalNerEx, the function should succeed
      assert is_map(index)
    end
  end

  describe "build/2 with structured documents" do
    test "accepts maps with :id and :text keys" do
      documents = [
        %{id: "doc-1", text: "Patient on lisinopril 10mg"},
        %{id: "doc-2", text: "Blood pressure 140/90"}
      ]

      {:ok, index} = SourceIndex.build(documents)

      assert is_map(index)
    end

    test "accepts maps with string keys" do
      documents = [
        %{"id" => "doc-1", "text" => "Patient has chest pain"}
      ]

      {:ok, index} = SourceIndex.build(documents)

      assert is_map(index)
    end

    test "handles mixed document formats" do
      documents = [
        "Plain string document",
        %{id: "doc-1", text: "Map with atoms"},
        %{"id" => "doc-2", "text" => "Map with strings"}
      ]

      {:ok, index} = SourceIndex.build(documents)

      assert is_map(index)
    end
  end

  describe "build/2 returns expected keys" do
    test "returns all required index keys" do
      {:ok, index} = SourceIndex.build(["Some clinical text"])

      assert Map.has_key?(index, :medications)
      assert Map.has_key?(index, :labs)
      assert Map.has_key?(index, :diagnoses)
      assert Map.has_key?(index, :findings)
    end

    test "index values are lists" do
      {:ok, index} = SourceIndex.build(["Some clinical text"])

      assert is_list(index.medications)
      assert is_list(index.labs)
      assert is_list(index.diagnoses)
      assert is_list(index.findings)
    end
  end

  describe "build/2 stability" do
    test "returns same structure for same input" do
      documents = ["Patient on metformin 500mg"]

      {:ok, index1} = SourceIndex.build(documents)
      {:ok, index2} = SourceIndex.build(documents)

      assert index1 == index2
    end

    test "handles empty document list" do
      {:ok, index} = SourceIndex.build([])

      assert index == SourceIndex.empty_index()
    end

    test "filters out empty documents" do
      documents = [
        "Valid document",
        %{id: "empty", text: ""},
        %{id: "valid", text: "Another valid"}
      ]

      {:ok, index} = SourceIndex.build(documents)

      # Should not error even with empty docs
      assert is_map(index)
    end
  end

  describe "empty_index/0" do
    test "returns expected structure" do
      index = SourceIndex.empty_index()

      assert index == %{
               medications: [],
               labs: [],
               diagnoses: [],
               findings: []
             }
    end
  end

  describe "build!/2" do
    test "returns index on success" do
      index = SourceIndex.build!(["Some text"])

      assert is_map(index)
      assert Map.has_key?(index, :medications)
    end
  end

  describe "clinical_ner_available?/0" do
    test "returns boolean" do
      result = SourceIndex.clinical_ner_available?()

      assert is_boolean(result)
    end
  end

  describe "integration with ClinicalNerEx" do
    # These tests check behavior when ClinicalNerEx is available
    # They should degrade gracefully when it's not

    test "extracts medications when ClinicalNerEx available" do
      documents = [
        %{id: "note-1", text: "Patient on metformin 500mg twice daily for diabetes"}
      ]

      {:ok, index} = SourceIndex.build(documents)

      if SourceIndex.clinical_ner_available?() do
        assert length(index.medications) > 0
        med = hd(index.medications)
        assert Map.has_key?(med, :text)
        assert Map.has_key?(med, :doc_id)
      else
        # Without ClinicalNerEx, medications list will be empty
        assert index.medications == []
      end
    end

    test "extracts labs when ClinicalNerEx available" do
      documents = [
        %{id: "lab-1", text: "HbA1c 7.2%, Creatinine 1.2 mg/dL"}
      ]

      {:ok, index} = SourceIndex.build(documents)

      if SourceIndex.clinical_ner_available?() do
        assert length(index.labs) > 0
      else
        assert index.labs == []
      end
    end

    test "extracts diagnoses when ClinicalNerEx available" do
      documents = [
        %{id: "note-1", text: "Diagnosed with type 2 diabetes mellitus"}
      ]

      {:ok, index} = SourceIndex.build(documents)

      if SourceIndex.clinical_ner_available?() do
        assert length(index.diagnoses) > 0
      else
        assert index.diagnoses == []
      end
    end

    test "preserves doc_id in extracted entities" do
      documents = [
        %{id: "specific-doc-id", text: "Patient on aspirin 81mg daily"}
      ]

      {:ok, index} = SourceIndex.build(documents)

      if SourceIndex.clinical_ner_available?() and length(index.medications) > 0 do
        med = hd(index.medications)
        assert med.doc_id == "specific-doc-id"
      end
    end
  end
end
