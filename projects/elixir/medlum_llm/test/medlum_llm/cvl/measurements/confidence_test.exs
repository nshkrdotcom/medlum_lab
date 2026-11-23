defmodule MedlumLlm.CVL.Measurements.ConfidenceTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.CVL.Measurements.Confidence

  describe "compute/1" do
    test "returns low confidence without consensus" do
      sample = make_sample(%{})

      {:ok, results} = Confidence.compute([sample])

      result = results[sample.id]
      assert result.confidence_level == :low
      assert result.score == 0.5
    end

    test "computes confidence from consensus" do
      sample = make_sample(%{
        consensus: %{
          verdict: :entailment,
          confidence: 0.9,
          agreement: 0.85,
          weighted_votes: %{entailment: 2.5, contradiction: 0.0, neutral: 0.5}
        }
      })

      {:ok, results} = Confidence.compute([sample])

      result = results[sample.id]
      assert result.score > 0.7
    end

    test "categorizes high confidence correctly" do
      sample = make_sample(%{
        consensus: %{
          verdict: :entailment,
          confidence: 0.95,
          agreement: 0.9,
          weighted_votes: %{entailment: 3.0, contradiction: 0.0, neutral: 0.0}
        }
      })

      {:ok, results} = Confidence.compute([sample])

      result = results[sample.id]
      assert result.confidence_level == :high
    end

    test "categorizes medium confidence correctly" do
      sample = make_sample(%{
        consensus: %{
          verdict: :entailment,
          confidence: 0.7,
          agreement: 0.6,
          weighted_votes: %{entailment: 2.0, contradiction: 0.5, neutral: 0.5}
        }
      })

      {:ok, results} = Confidence.compute([sample])

      result = results[sample.id]
      assert result.confidence_level == :medium
    end

    test "categorizes low confidence correctly" do
      sample = make_sample(%{
        consensus: %{
          verdict: :neutral,
          confidence: 0.4,
          agreement: 0.4,
          weighted_votes: %{entailment: 0.5, contradiction: 0.5, neutral: 1.0}
        }
      })

      {:ok, results} = Confidence.compute([sample])

      result = results[sample.id]
      assert result.confidence_level == :low
    end

    test "includes all components" do
      sample = make_sample(%{
        consensus: %{
          verdict: :entailment,
          confidence: 0.85,
          agreement: 0.8,
          weighted_votes: %{entailment: 2.5, contradiction: 0.0, neutral: 0.5}
        }
      })

      {:ok, results} = Confidence.compute([sample])

      result = results[sample.id]
      assert Map.has_key?(result.components, :agreement_score)
      assert Map.has_key?(result.components, :strength_score)
    end

    test "applies entropy adjustment" do
      # High entropy (disagreement) sample
      sample_high_entropy = make_sample(%{
        consensus: %{
          verdict: :neutral,
          confidence: 0.5,
          agreement: 0.4,
          weighted_votes: %{entailment: 1.0, contradiction: 1.0, neutral: 1.0}
        }
      })

      # Low entropy (agreement) sample
      sample_low_entropy = make_sample(%{
        consensus: %{
          verdict: :entailment,
          confidence: 0.5,
          agreement: 0.4,
          weighted_votes: %{entailment: 3.0, contradiction: 0.0, neutral: 0.0}
        }
      })

      {:ok, results_high} = Confidence.compute([sample_high_entropy])
      {:ok, results_low} = Confidence.compute([sample_low_entropy])

      # High entropy should result in lower confidence
      assert results_high[sample_high_entropy.id].calibrated_score <=
               results_low[sample_low_entropy.id].calibrated_score
    end

    test "processes multiple samples" do
      samples = [
        make_sample(%{consensus: %{verdict: :entailment, confidence: 0.9, agreement: 0.85}}),
        make_sample(%{consensus: %{verdict: :contradiction, confidence: 0.8, agreement: 0.7}})
      ]

      {:ok, results} = Confidence.compute(samples)

      assert map_size(results) == 2
    end
  end

  describe "dependencies/0" do
    test "depends on AgentConsensus" do
      deps = Confidence.dependencies()

      assert MedlumLlm.CVL.Measurements.AgentConsensus in deps
    end
  end

  describe "thresholds/0" do
    test "returns high and low thresholds" do
      thresholds = Confidence.thresholds()

      assert thresholds.high > thresholds.low
      assert thresholds.high <= 1.0
      assert thresholds.low >= 0.0
    end
  end

  describe "key/0" do
    test "returns stable key" do
      assert String.starts_with?(Confidence.key(), "confidence_")
    end
  end

  defp make_sample(measurements) do
    %Forge.Sample{
      id: "test_#{System.unique_integer()}",
      pipeline: :test,
      data: %{},
      measurements: measurements,
      status: :pending,
      created_at: DateTime.utc_now()
    }
  end
end
