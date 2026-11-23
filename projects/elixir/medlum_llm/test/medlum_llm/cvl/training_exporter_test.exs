defmodule MedlumLlm.CVL.TrainingExporterTest do
  use ExUnit.Case

  alias MedlumLlm.CVL.TrainingExporter

  # Helper to create mock claim results
  defp mock_claim_result(verdict, confidence, claim_text \\ "Test claim") do
    %{
      claim: %{id: "c1", text: claim_text, source_offset: 0, source_length: 10},
      verdict: verdict,
      confidence: confidence,
      needs_review: verdict in [:contradiction, :neutral],
      agent_results: [
        %{
          agent: :medication_agent,
          weight: 1.5,
          result: %{
            verdict: verdict,
            confidence: confidence,
            explanations: ["Test explanation"],
            evidence: [%{snippet: "evidence snippet", doc_id: "doc-1"}],
            sub_verdicts: []
          }
        }
      ],
      scores: %{entailment: 0.0, contradiction: 0.0, neutral: 0.0}
    }
  end

  describe "select_candidates/2" do
    test "selects all contradiction claims" do
      claim_results = [
        mock_claim_result(:contradiction, 0.9),
        mock_claim_result(:entailment, 0.95),
        mock_claim_result(:contradiction, 0.6)
      ]

      candidates = TrainingExporter.select_candidates(claim_results)

      assert length(candidates) == 2
      assert Enum.all?(candidates, &(&1.verdict == :contradiction))
    end

    test "selects low-confidence neutral claims" do
      claim_results = [
        mock_claim_result(:neutral, 0.5),
        mock_claim_result(:neutral, 0.8),
        mock_claim_result(:entailment, 0.9)
      ]

      candidates = TrainingExporter.select_candidates(claim_results)

      # Only the low-confidence neutral (0.5 < 0.7 threshold)
      assert length(candidates) == 1
      assert hd(candidates).confidence == 0.5
    end

    test "does not select high-confidence neutral claims" do
      claim_results = [
        mock_claim_result(:neutral, 0.9)
      ]

      candidates = TrainingExporter.select_candidates(claim_results)

      assert candidates == []
    end

    test "does not select entailment claims" do
      claim_results = [
        mock_claim_result(:entailment, 0.95),
        mock_claim_result(:entailment, 0.6)
      ]

      candidates = TrainingExporter.select_candidates(claim_results)

      assert candidates == []
    end

    test "respects custom neutral_threshold" do
      claim_results = [
        mock_claim_result(:neutral, 0.5),
        mock_claim_result(:neutral, 0.8)
      ]

      # With threshold 0.9, both should be selected
      candidates = TrainingExporter.select_candidates(claim_results, neutral_threshold: 0.9)

      assert length(candidates) == 2
    end

    test "handles empty input" do
      candidates = TrainingExporter.select_candidates([])

      assert candidates == []
    end
  end

  describe "candidate format" do
    test "includes required fields" do
      claim_results = [mock_claim_result(:contradiction, 0.85, "Patient on unknowndrugxyz")]

      [candidate] = TrainingExporter.select_candidates(claim_results)

      assert Map.has_key?(candidate, :id)
      assert Map.has_key?(candidate, :claim_text)
      assert Map.has_key?(candidate, :verdict)
      assert Map.has_key?(candidate, :confidence)
      assert Map.has_key?(candidate, :agent_results)
      assert Map.has_key?(candidate, :evidence_snippets)
    end

    test "extracts claim text" do
      claim_results = [mock_claim_result(:contradiction, 0.85, "Specific claim text")]

      [candidate] = TrainingExporter.select_candidates(claim_results)

      assert candidate.claim_text == "Specific claim text"
    end

    test "extracts evidence snippets" do
      claim_results = [mock_claim_result(:contradiction, 0.85)]

      [candidate] = TrainingExporter.select_candidates(claim_results)

      assert "evidence snippet" in candidate.evidence_snippets
    end

    test "formats agent results minimally" do
      claim_results = [mock_claim_result(:contradiction, 0.85)]

      [candidate] = TrainingExporter.select_candidates(claim_results)

      agent_result = hd(candidate.agent_results)

      assert Map.has_key?(agent_result, :agent)
      assert Map.has_key?(agent_result, :weight)
      assert Map.has_key?(agent_result, :verdict)
      assert Map.has_key?(agent_result, :confidence)
      assert Map.has_key?(agent_result, :explanations)
    end
  end

  describe "to_jsonl/1" do
    test "returns valid JSONL string" do
      claim_results = [
        mock_claim_result(:contradiction, 0.85, "First claim"),
        mock_claim_result(:contradiction, 0.75, "Second claim")
      ]

      candidates = TrainingExporter.select_candidates(claim_results)
      jsonl = TrainingExporter.to_jsonl(candidates)

      lines = String.split(jsonl, "\n", trim: true)

      assert length(lines) == 2

      # Each line should be valid JSON
      for line <- lines do
        assert {:ok, _} = Jason.decode(line)
      end
    end

    test "includes claim_text in output" do
      claim_results = [mock_claim_result(:contradiction, 0.85, "Test claim text")]

      candidates = TrainingExporter.select_candidates(claim_results)
      jsonl = TrainingExporter.to_jsonl(candidates)

      assert String.contains?(jsonl, "Test claim text")
    end

    test "converts verdict to string" do
      claim_results = [mock_claim_result(:contradiction, 0.85)]

      candidates = TrainingExporter.select_candidates(claim_results)
      jsonl = TrainingExporter.to_jsonl(candidates)

      assert String.contains?(jsonl, "\"verdict\":\"contradiction\"")
    end

    test "handles empty candidates" do
      jsonl = TrainingExporter.to_jsonl([])

      assert jsonl == ""
    end
  end

  describe "to_maps/1" do
    test "returns list of maps" do
      claim_results = [mock_claim_result(:contradiction, 0.85)]

      candidates = TrainingExporter.select_candidates(claim_results)
      maps = TrainingExporter.to_maps(candidates)

      assert is_list(maps)
      assert length(maps) == 1
      assert is_map(hd(maps))
    end

    test "uses string keys for JSON compatibility" do
      claim_results = [mock_claim_result(:contradiction, 0.85)]

      candidates = TrainingExporter.select_candidates(claim_results)
      [map] = TrainingExporter.to_maps(candidates)

      assert Map.has_key?(map, "id")
      assert Map.has_key?(map, "claim_text")
      assert Map.has_key?(map, "verdict")
    end
  end

  describe "write_jsonl/3" do
    @tag :tmp_dir
    test "writes to file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "test_export.jsonl")

      claim_results = [mock_claim_result(:contradiction, 0.85)]
      candidates = TrainingExporter.select_candidates(claim_results)

      assert :ok = TrainingExporter.write_jsonl(candidates, path)
      assert File.exists?(path)

      content = File.read!(path)
      assert String.contains?(content, "contradiction")
    end

    @tag :tmp_dir
    test "appends when append option is true", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "append_test.jsonl")

      claim1 = [mock_claim_result(:contradiction, 0.85, "First")]
      claim2 = [mock_claim_result(:contradiction, 0.75, "Second")]

      candidates1 = TrainingExporter.select_candidates(claim1)
      candidates2 = TrainingExporter.select_candidates(claim2)

      TrainingExporter.write_jsonl(candidates1, path)
      TrainingExporter.write_jsonl(candidates2, path, append: true)

      content = File.read!(path)
      lines = String.split(content, "\n", trim: true)

      assert length(lines) == 2
    end
  end

  describe "summarize/1" do
    test "returns summary statistics" do
      claim_results = [
        mock_claim_result(:contradiction, 0.85),
        mock_claim_result(:contradiction, 0.75),
        mock_claim_result(:neutral, 0.5)
      ]

      candidates = TrainingExporter.select_candidates(claim_results)
      summary = TrainingExporter.summarize(candidates)

      assert summary.total_count == 3
      assert summary.contradiction_count == 2
      assert summary.neutral_count == 1
    end

    test "calculates average confidence" do
      claim_results = [
        mock_claim_result(:contradiction, 0.8),
        mock_claim_result(:contradiction, 0.6)
      ]

      candidates = TrainingExporter.select_candidates(claim_results)
      summary = TrainingExporter.summarize(candidates)

      assert summary.average_confidence == 0.7
    end

    test "handles empty candidates" do
      summary = TrainingExporter.summarize([])

      assert summary.total_count == 0
      assert summary.contradiction_count == 0
      assert summary.neutral_count == 0
      assert summary.average_confidence == 0.0
    end

    test "counts agent contradictions" do
      claim_results = [mock_claim_result(:contradiction, 0.85)]

      candidates = TrainingExporter.select_candidates(claim_results)
      summary = TrainingExporter.summarize(candidates)

      assert is_map(summary.agents_with_contradictions)
    end
  end

  describe "PHI considerations" do
    test "does not include full document text" do
      claim_results = [mock_claim_result(:contradiction, 0.85)]

      candidates = TrainingExporter.select_candidates(claim_results)
      jsonl = TrainingExporter.to_jsonl(candidates)

      # Should not have "documents" key
      refute String.contains?(jsonl, "\"documents\"")
    end

    test "only includes evidence snippets not full docs" do
      claim_results = [mock_claim_result(:contradiction, 0.85)]

      [candidate] = TrainingExporter.select_candidates(claim_results)

      # Should have snippets, not full documents
      assert Map.has_key?(candidate, :evidence_snippets)
      refute Map.has_key?(candidate, :documents)
      refute Map.has_key?(candidate, :source_documents)
    end
  end
end
