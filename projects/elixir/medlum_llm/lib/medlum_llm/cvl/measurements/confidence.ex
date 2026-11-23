defmodule MedlumLlm.CVL.Measurements.Confidence do
  @moduledoc """
  Forge Measurement for calibrated confidence score computation.

  This measurement depends on `AgentConsensus` and computes a calibrated
  confidence score that can be used for:
  - Training sample weighting
  - Active learning prioritization
  - Threshold-based routing to human review
  - Quality filtering for export

  ## Confidence Components

  1. **Agreement Score** (60% weight) - How well agents agree
  2. **Strength Score** (40% weight) - Average confidence of winning verdict

  ## Calibration

  The raw confidence is calibrated using Platt scaling to ensure that
  predicted probabilities match empirical frequencies.

  ## Thresholds

  - `>= 0.85` - High confidence (auto-accept)
  - `0.5 - 0.85` - Medium confidence (may need review)
  - `< 0.5` - Low confidence (requires human review)

  ## Example

      iex> samples = [%Forge.Sample{
      ...>   measurements: %{
      ...>     consensus: %{verdict: :entailment, confidence: 0.9, agreement: 0.8}
      ...>   }
      ...> }]
      iex> {:ok, results} = Confidence.compute(samples)
      iex> results["sample_id"].score >= 0.8
      true
  """

  @behaviour Forge.Measurement

  alias MedlumLlm.CVL.Measurements.AgentConsensus

  @measurement_version 1

  # Weight factors for confidence components
  @agreement_weight 0.6
  @strength_weight 0.4

  # Platt scaling parameters (would be learned from calibration data)
  @platt_a 1.0
  @platt_b 0.0

  # Confidence thresholds
  @high_threshold 0.85
  @low_threshold 0.5

  @type result :: %{
          score: float(),
          calibrated_score: float(),
          components: map(),
          confidence_level: :high | :medium | :low,
          reasoning: String.t()
        }

  @impl true
  @spec compute([Forge.Sample.t()]) :: {:ok, map()} | {:error, term()}
  def compute(samples) do
    results =
      samples
      |> Enum.map(fn sample ->
        confidence = compute_confidence(sample)
        {sample.id, confidence}
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

    "confidence_#{config_hash}"
  end

  @impl true
  @spec version() :: pos_integer()
  def version, do: @measurement_version

  @impl true
  @spec dependencies() :: [module()]
  def dependencies, do: [AgentConsensus]

  @impl true
  @spec async?() :: boolean()
  def async?, do: false

  @impl true
  @spec timeout() :: pos_integer()
  def timeout, do: 10_000

  @doc """
  Get current configuration for this measurement.
  """
  @spec config() :: map()
  def config do
    %{
      agreement_weight: @agreement_weight,
      strength_weight: @strength_weight,
      high_threshold: @high_threshold,
      low_threshold: @low_threshold,
      platt_a: @platt_a,
      platt_b: @platt_b
    }
  end

  @doc """
  Get confidence thresholds.
  """
  @spec thresholds() :: %{high: float(), low: float()}
  def thresholds do
    %{high: @high_threshold, low: @low_threshold}
  end

  # Private functions

  @spec compute_confidence(Forge.Sample.t()) :: result()
  defp compute_confidence(sample) do
    consensus = get_consensus(sample)

    if is_nil(consensus) do
      %{
        score: 0.5,
        calibrated_score: 0.5,
        components: %{
          agreement_score: 0.0,
          strength_score: 0.0
        },
        confidence_level: :low,
        reasoning: "No consensus measurement available"
      }
    else
      compute_from_consensus(consensus)
    end
  end

  @spec get_consensus(Forge.Sample.t()) :: map() | nil
  defp get_consensus(sample) do
    case sample.measurements do
      %{consensus: consensus} -> consensus
      _ -> nil
    end
  end

  @spec compute_from_consensus(map()) :: result()
  defp compute_from_consensus(consensus) do
    # Extract components
    agreement_score = Map.get(consensus, :agreement, 0.5)
    strength_score = Map.get(consensus, :confidence, 0.5)

    # Compute raw confidence
    raw_score = @agreement_weight * agreement_score + @strength_weight * strength_score

    # Apply entropy adjustment
    entropy_adjusted = apply_entropy_adjustment(raw_score, consensus)

    # Calibrate using Platt scaling
    calibrated = platt_calibrate(entropy_adjusted)

    # Determine confidence level
    level = categorize_confidence(calibrated)

    %{
      score: raw_score,
      calibrated_score: calibrated,
      components: %{
        agreement_score: agreement_score,
        strength_score: strength_score,
        entropy_adjustment: entropy_adjusted - raw_score,
        verdict: Map.get(consensus, :verdict, :neutral)
      },
      confidence_level: level,
      reasoning: format_reasoning(calibrated, level, consensus)
    }
  end

  @spec apply_entropy_adjustment(float(), map()) :: float()
  defp apply_entropy_adjustment(raw_score, consensus) do
    # Reduce confidence when agent verdicts are highly diverse
    weighted_votes = Map.get(consensus, :weighted_votes, %{})

    if map_size(weighted_votes) == 0 do
      raw_score
    else
      # Compute normalized entropy of vote distribution
      total = Enum.sum(Map.values(weighted_votes))

      if total > 0 do
        entropy =
          weighted_votes
          |> Map.values()
          |> Enum.filter(&(&1 > 0))
          |> Enum.map(fn vote ->
            p = vote / total
            -p * :math.log2(p)
          end)
          |> Enum.sum()

        # Max entropy for 3 categories is log2(3) ≈ 1.585
        max_entropy = :math.log2(3)
        normalized_entropy = entropy / max_entropy

        # Reduce confidence proportionally to entropy
        raw_score * (1.0 - 0.2 * normalized_entropy)
      else
        raw_score
      end
    end
  end

  @spec platt_calibrate(float()) :: float()
  defp platt_calibrate(score) do
    # Apply Platt scaling: 1 / (1 + exp(A * score + B))
    # For now, use identity-like transformation since we don't have calibration data
    logit = @platt_a * (score - 0.5) + @platt_b
    sigmoid(logit)
  end

  @spec sigmoid(float()) :: float()
  defp sigmoid(x) do
    1.0 / (1.0 + :math.exp(-x))
  end

  @spec categorize_confidence(float()) :: :high | :medium | :low
  defp categorize_confidence(score) do
    cond do
      score >= @high_threshold -> :high
      score >= @low_threshold -> :medium
      true -> :low
    end
  end

  @spec format_reasoning(float(), atom(), map()) :: String.t()
  defp format_reasoning(score, level, consensus) do
    verdict = Map.get(consensus, :verdict, :unknown)
    agreement = Map.get(consensus, :agreement, 0.0)

    level_description =
      case level do
        :high -> "auto-accept eligible"
        :medium -> "may benefit from review"
        :low -> "requires human verification"
      end

    "Confidence #{Float.round(score * 100, 1)}% (#{level}): #{verdict} with #{Float.round(agreement * 100, 1)}% agreement. Sample #{level_description}."
  end
end
