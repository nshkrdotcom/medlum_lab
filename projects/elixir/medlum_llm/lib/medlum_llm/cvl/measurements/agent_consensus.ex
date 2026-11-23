defmodule MedlumLlm.CVL.Measurements.AgentConsensus do
  @moduledoc """
  Forge Measurement for aggregating CVL agent verdicts using weighted voting.

  This measurement depends on all five CVL agent measurements and computes
  a consensus verdict using configurable weights. The consensus is determined
  by majority voting with confidence-weighted contributions.

  ## Dependencies

  - `MedicationAgent` - RxNorm verification
  - `LabAgent` - LOINC verification
  - `OntologyAgent` - SNOMED-CT/ICD-10 verification
  - `TemporalAgent` - Timeline consistency
  - `DifferentialAgent` - Symptom-diagnosis mapping

  ## Consensus Strategy

  1. Collect verdicts from all agents
  2. Weight each verdict by agent-specific weight and confidence
  3. Compute weighted vote for each verdict type
  4. Select verdict with highest weighted vote
  5. Compute agreement score as measure of consensus strength

  ## Example

      iex> samples = [%Forge.Sample{
      ...>   measurements: %{
      ...>     medication: %{verdict: :entailment, confidence: 0.9},
      ...>     lab: %{verdict: :entailment, confidence: 0.85},
      ...>     ontology: %{verdict: :contradiction, confidence: 0.7}
      ...>   }
      ...> }]
      iex> {:ok, results} = AgentConsensus.compute(samples)
      iex> results["sample_id"].verdict
      :entailment
  """

  @behaviour Forge.Measurement

  alias MedlumLlm.CVL.Measurements.{
    MedicationAgent,
    LabAgent,
    OntologyAgent,
    TemporalAgent,
    DifferentialAgent
  }

  @measurement_version 1

  # Agent weights for voting
  @agent_weights %{
    medication: 1.2,
    lab: 1.1,
    ontology: 1.3,
    temporal: 0.9,
    differential: 1.0
  }

  @agent_modules [
    MedicationAgent,
    LabAgent,
    OntologyAgent,
    TemporalAgent,
    DifferentialAgent
  ]

  @type verdict :: :entailment | :contradiction | :neutral

  @type result :: %{
          verdict: verdict(),
          confidence: float(),
          agreement: float(),
          agent_verdicts: map(),
          weighted_votes: map(),
          reasoning: String.t()
        }

  @impl true
  @spec compute([Forge.Sample.t()]) :: {:ok, map()} | {:error, term()}
  def compute(samples) do
    results =
      samples
      |> Enum.map(fn sample ->
        consensus = compute_consensus(sample)
        {sample.id, consensus}
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

    "agent_consensus_#{config_hash}"
  end

  @impl true
  @spec version() :: pos_integer()
  def version, do: @measurement_version

  @impl true
  @spec dependencies() :: [module()]
  def dependencies, do: @agent_modules

  @impl true
  @spec async?() :: boolean()
  def async?, do: false

  @impl true
  @spec timeout() :: pos_integer()
  def timeout, do: 30_000

  @doc """
  Get current configuration for this measurement.
  """
  @spec config() :: map()
  def config do
    %{
      agent_weights: @agent_weights,
      min_agents_required: 2,
      contradiction_veto: true
    }
  end

  # Private functions

  @spec compute_consensus(Forge.Sample.t()) :: result()
  defp compute_consensus(sample) do
    # Collect agent verdicts from measurements
    agent_verdicts = collect_agent_verdicts(sample)

    if map_size(agent_verdicts) < 2 do
      %{
        verdict: :neutral,
        confidence: 0.5,
        agreement: 0.0,
        agent_verdicts: agent_verdicts,
        weighted_votes: %{},
        reasoning: "Insufficient agent verdicts for consensus"
      }
    else
      compute_weighted_consensus(agent_verdicts)
    end
  end

  @spec collect_agent_verdicts(Forge.Sample.t()) :: map()
  defp collect_agent_verdicts(sample) do
    measurements = sample.measurements || %{}

    [:medication, :lab, :ontology, :temporal, :differential]
    |> Enum.map(fn agent_key ->
      case Map.get(measurements, agent_key) do
        %{verdict: verdict, confidence: confidence} = result ->
          {agent_key,
           %{
             verdict: verdict,
             confidence: confidence,
             reasoning: Map.get(result, :reasoning, "")
           }}

        %{verdict: verdict} = result ->
          {agent_key,
           %{
             verdict: verdict,
             confidence: Map.get(result, :confidence, 0.5),
             reasoning: Map.get(result, :reasoning, "")
           }}

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  @spec compute_weighted_consensus(map()) :: result()
  defp compute_weighted_consensus(agent_verdicts) do
    # Check for contradiction veto
    contradiction_count =
      agent_verdicts
      |> Enum.count(fn {_agent, %{verdict: verdict}} -> verdict == :contradiction end)

    if config()[:contradiction_veto] and contradiction_count >= 2 do
      # Two or more contradictions means overall contradiction
      avg_confidence = average_confidence(agent_verdicts, :contradiction)

      %{
        verdict: :contradiction,
        confidence: avg_confidence,
        agreement: contradiction_count / map_size(agent_verdicts),
        agent_verdicts: agent_verdicts,
        weighted_votes: %{contradiction: 1.0},
        reasoning: "Multiple agents detected contradictions (veto applied)"
      }
    else
      # Compute weighted votes
      weighted_votes = compute_weighted_votes(agent_verdicts)

      # Select winning verdict
      {winning_verdict, winning_score} =
        weighted_votes
        |> Enum.max_by(fn {_verdict, score} -> score end)

      total_score =
        weighted_votes
        |> Map.values()
        |> Enum.sum()

      # Compute confidence based on weighted average of contributing agents
      confidence = compute_consensus_confidence(agent_verdicts, winning_verdict)

      # Compute agreement score
      agreement =
        if total_score > 0 do
          winning_score / total_score
        else
          0.0
        end

      %{
        verdict: winning_verdict,
        confidence: confidence,
        agreement: agreement,
        agent_verdicts: agent_verdicts,
        weighted_votes: weighted_votes,
        reasoning: format_reasoning(agent_verdicts, winning_verdict, agreement)
      }
    end
  end

  @spec compute_weighted_votes(map()) :: map()
  defp compute_weighted_votes(agent_verdicts) do
    # Initialize vote counters
    votes = %{entailment: 0.0, contradiction: 0.0, neutral: 0.0}

    Enum.reduce(agent_verdicts, votes, fn {agent, %{verdict: verdict, confidence: confidence}},
                                          acc ->
      weight = Map.get(@agent_weights, agent, 1.0)
      weighted_vote = weight * confidence

      Map.update!(acc, verdict, &(&1 + weighted_vote))
    end)
  end

  @spec compute_consensus_confidence(map(), verdict()) :: float()
  defp compute_consensus_confidence(agent_verdicts, winning_verdict) do
    matching_agents =
      agent_verdicts
      |> Enum.filter(fn {_agent, %{verdict: verdict}} -> verdict == winning_verdict end)

    if Enum.empty?(matching_agents) do
      0.5
    else
      # Weighted average of confidences
      {total_weighted_conf, total_weight} =
        Enum.reduce(matching_agents, {0.0, 0.0}, fn {agent, %{confidence: confidence}},
                                                    {conf_sum, weight_sum} ->
          weight = Map.get(@agent_weights, agent, 1.0)
          {conf_sum + confidence * weight, weight_sum + weight}
        end)

      if total_weight > 0 do
        total_weighted_conf / total_weight
      else
        0.5
      end
    end
  end

  @spec average_confidence(map(), verdict()) :: float()
  defp average_confidence(agent_verdicts, target_verdict) do
    matching =
      agent_verdicts
      |> Enum.filter(fn {_agent, %{verdict: verdict}} -> verdict == target_verdict end)
      |> Enum.map(fn {_agent, %{confidence: conf}} -> conf end)

    if Enum.empty?(matching) do
      0.5
    else
      Enum.sum(matching) / length(matching)
    end
  end

  @spec format_reasoning(map(), verdict(), float()) :: String.t()
  defp format_reasoning(agent_verdicts, verdict, agreement) do
    agent_count = map_size(agent_verdicts)

    verdict_counts =
      agent_verdicts
      |> Enum.map(fn {_agent, %{verdict: v}} -> v end)
      |> Enum.frequencies()

    verdict_summary =
      verdict_counts
      |> Enum.map(fn {v, count} -> "#{count} #{v}" end)
      |> Enum.join(", ")

    "Consensus #{verdict} from #{agent_count} agents (#{verdict_summary}). Agreement: #{Float.round(agreement * 100, 1)}%"
  end
end
