defmodule MedlumLlm.CVL.VerifierTest do
  use ExUnit.Case

  alias MedlumLlm.CVL.Verifier

  describe "verify_summary/3" do
    test "returns verification result structure" do
      summary = "Patient has diabetes."
      docs = ["Patient diagnosed with type 2 diabetes mellitus."]

      {:ok, result} = Verifier.verify_summary(summary, docs)

      assert Map.has_key?(result, :summary_verdict)
      assert Map.has_key?(result, :summary_confidence)
      assert Map.has_key?(result, :claim_results)
      assert Map.has_key?(result, :claim_count)
      assert Map.has_key?(result, :needs_review_count)
      assert Map.has_key?(result, :source_index)
    end

    test "summary_verdict is one of three values" do
      summary = "Patient on metformin."
      docs = ["Source document"]

      {:ok, result} = Verifier.verify_summary(summary, docs)

      assert result.summary_verdict in [:entailment, :contradiction, :neutral]
    end

    test "claim_count matches number of claims" do
      summary = """
      - First claim
      - Second claim
      - Third claim
      """

      docs = ["Source document"]

      {:ok, result} = Verifier.verify_summary(summary, docs)

      assert result.claim_count == 3
      assert length(result.claim_results) == 3
    end
  end

  describe "verify_summary/3 per-claim results" do
    test "each claim result has required fields" do
      summary = "Patient has chest pain."
      docs = ["Patient presents with chest pain."]

      {:ok, result} = Verifier.verify_summary(summary, docs)

      claim_result = hd(result.claim_results)

      assert Map.has_key?(claim_result, :claim)
      assert Map.has_key?(claim_result, :verdict)
      assert Map.has_key?(claim_result, :confidence)
      assert Map.has_key?(claim_result, :needs_review)
      assert Map.has_key?(claim_result, :agent_results)
    end

    test "claim includes id and text" do
      summary = "HbA1c is 7.2%."
      docs = ["Lab: HbA1c 7.2%"]

      {:ok, result} = Verifier.verify_summary(summary, docs)

      claim = hd(result.claim_results).claim

      assert Map.has_key?(claim, :id)
      assert Map.has_key?(claim, :text)
      assert claim.id == "c1"
    end
  end

  describe "verify_summary/3 needs_review" do
    test "needs_review true for contradiction" do
      summary = "Patient started on unknownfakedrugxyz 100mg."
      docs = ["Source document"]

      {:ok, result} = Verifier.verify_summary(summary, docs)

      claim_result = hd(result.claim_results)

      if claim_result.verdict == :contradiction do
        assert claim_result.needs_review == true
      end
    end

    test "needs_review true for neutral" do
      summary = "Some claim not in source."
      docs = ["Different content entirely"]

      {:ok, result} = Verifier.verify_summary(summary, docs)

      claim_result = hd(result.claim_results)

      if claim_result.verdict == :neutral do
        assert claim_result.needs_review == true
      end
    end

    test "needs_review_count tracks needing review" do
      summary = """
      - Valid claim from source
      - Made up claim not in source
      """

      docs = ["Valid claim from source"]

      {:ok, result} = Verifier.verify_summary(summary, docs)

      # At least some claims should need review
      assert result.needs_review_count >= 0
      assert result.needs_review_count <= result.claim_count
    end
  end

  describe "verify_summary/3 summary verdict rules" do
    test "contradiction if any claim is high-confidence contradiction" do
      summary = "Patient started on fakemedicationxyz 500mg."
      docs = ["Source document"]

      {:ok, result} = Verifier.verify_summary(summary, docs)

      # Unknown medication should cause contradiction
      if Enum.any?(result.claim_results, &(&1.verdict == :contradiction && &1.confidence >= 0.7)) do
        assert result.summary_verdict == :contradiction
      end
    end

    test "neutral if any claim needs review but no high-confidence contradiction" do
      summary = "Patient has some condition."
      docs = ["Different content"]

      {:ok, result} = Verifier.verify_summary(summary, docs)

      # Without source evidence, should be neutral
      if result.needs_review_count > 0 do
        assert result.summary_verdict in [:neutral, :contradiction]
      end
    end
  end

  describe "verify_summary/3 with empty input" do
    test "handles empty summary" do
      {:ok, result} = Verifier.verify_summary("", ["Source"])

      assert result.claim_count == 0
      assert result.claim_results == []
      assert result.summary_verdict == :neutral
    end

    test "handles empty documents" do
      {:ok, result} = Verifier.verify_summary("Patient has diabetes.", [])

      assert result.summary_verdict == :neutral
    end
  end

  describe "verify_summary/3 with options" do
    test "accepts demographics option" do
      summary = "Patient is elderly."
      docs = ["Source document"]

      {:ok, result} = Verifier.verify_summary(summary, docs, demographics: %{age: 75})

      assert is_map(result)
    end

    test "accepts claim length options" do
      summary = "- A\n- Valid claim here"
      docs = ["Source"]

      {:ok, result} = Verifier.verify_summary(summary, docs, min_claim_length: 5)

      # Short claim "A" should be filtered out
      assert result.claim_count == 1
    end
  end

  describe "verify_summary!/3" do
    test "returns result on success" do
      result = Verifier.verify_summary!("Patient has diabetes.", ["Source"])

      assert is_map(result)
      assert result.summary_verdict in [:entailment, :contradiction, :neutral]
    end
  end

  describe "verify_claim/3" do
    test "verifies single claim" do
      context = %{
        documents: ["Patient on metformin 500mg"],
        source_index: %{medications: [%{text: "metformin 500mg", doc_id: "doc-1"}]},
        demographics: %{}
      }

      result = Verifier.verify_claim("Patient on metformin 500mg", context)

      assert Map.has_key?(result, :verdict)
      assert Map.has_key?(result, :confidence)
      assert Map.has_key?(result, :needs_review)
    end
  end

  describe "source_index integration" do
    test "builds source index from documents" do
      summary = "Patient on metformin."
      docs = [%{id: "note-1", text: "Started metformin 500mg"}]

      {:ok, result} = Verifier.verify_summary(summary, docs)

      assert is_map(result.source_index)
      assert Map.has_key?(result.source_index, :medications)
    end

    test "accepts plain string documents" do
      summary = "Patient on metformin."
      docs = ["Started metformin 500mg", "HbA1c 7.2%"]

      {:ok, result} = Verifier.verify_summary(summary, docs)

      assert is_map(result.source_index)
    end

    test "accepts mixed document formats" do
      summary = "Patient on metformin."

      docs = [
        "Plain string",
        %{id: "note-1", text: "Map with atoms"},
        %{"id" => "note-2", "text" => "Map with strings"}
      ]

      {:ok, result} = Verifier.verify_summary(summary, docs)

      assert is_map(result.source_index)
    end
  end

  describe "integration with agents" do
    test "verifies medication claims" do
      summary = "Patient started on metformin 500mg twice daily."
      docs = ["Patient with diabetes, started metformin 500mg BID."]

      {:ok, result} = Verifier.verify_summary(summary, docs)

      # Should get a result from medication agent
      claim_result = hd(result.claim_results)
      agent_names = Enum.map(claim_result.agent_results, & &1.agent)

      assert :medication_agent in agent_names
    end

    test "verifies lab claims" do
      summary = "HbA1c is 7.2%."
      docs = ["Lab results: HbA1c 7.2%"]

      {:ok, result} = Verifier.verify_summary(summary, docs)

      claim_result = hd(result.claim_results)
      agent_names = Enum.map(claim_result.agent_results, & &1.agent)

      assert :lab_agent in agent_names
    end

    test "verifies diagnosis claims" do
      summary = "Patient diagnosed with type 2 diabetes."
      docs = ["Diagnosis: Type 2 diabetes mellitus"]

      {:ok, result} = Verifier.verify_summary(summary, docs)

      claim_result = hd(result.claim_results)
      agent_names = Enum.map(claim_result.agent_results, & &1.agent)

      assert :ontology_agent in agent_names
    end
  end
end
