defmodule MedlumLlm.CVL.Consensus do
  @moduledoc """
  Runs all CVL agents in parallel and aggregates results via weighted scoring.

  The Consensus module orchestrates verification by running all 5 CVL agents
  concurrently using `Task.async_stream/3` and combines their results using
  Medlum-owned aggregation rules.

  ## Agents

  - `MedicationAgent` (weight: 1.5) - Safety-critical drug verification
  - `LabAgent` (weight: 1.2) - Lab value validation
  - `OntologyAgent` (weight: 1.0) - SNOMED/ICD-10 terminology
  - `TemporalAgent` (weight: 0.8) - Timeline consistency
  - `DifferentialAgent` (weight: 1.0) - Symptom-diagnosis mapping

  ## Aggregation Rules

  1. Compute weighted score per verdict: `agent.weight() * result.confidence`
  2. **Contradiction precedence**: If `contradiction_score > entailment_score * 0.5`
  3. **Entailment**: If `entailment_score > neutral_score`
  4. **Neutral**: Default when evidence is insufficient

  ## Examples

      iex> claim = "Patient started on metformin 500mg"
      iex> context = %{
      ...>   documents: ["Patient on metformin 500mg for diabetes"],
      ...>   source_index: %{medications: [%{text: "metformin 500mg", doc_id: "doc-1"}]}
      ...> }
      iex> result = Consensus.verify(claim, context)
      iex> result.verdict in [:entailment, :contradiction, :neutral]
      true

  """

  alias MedlumLlm.CVL.{
    MedicationAgent,
    LabAgent,
    OntologyAgent,
    TemporalAgent,
    DifferentialAgent
  }

  @type verdict :: :entailment | :contradiction | :neutral

  @type agent_result :: %{
          agent: atom(),
          weight: float(),
          result: MedlumLlm.CVL.Agent.result()
        }

  @type consensus_result :: %{
          verdict: verdict(),
          confidence: float(),
          agent_results: [agent_result()],
          scores: %{entailment: float(), contradiction: float(), neutral: float()}
        }

  @agents [
    MedicationAgent,
    LabAgent,
    OntologyAgent,
    TemporalAgent,
    DifferentialAgent
  ]

  @default_timeout 30_000

  @doc """
  Verify a claim against context using all CVL agents.

  ## Arguments

  - `claim` - The claim text to verify
  - `context` - Context map containing documents, source_index, demographics, etc.

  ## Options

  - `:timeout` - Timeout per agent in milliseconds (default: 30000)
  - `:agents` - List of agent modules to use (default: all 5 agents)

  ## Returns

  A consensus result map:

      %{
        verdict: :entailment | :contradiction | :neutral,
        confidence: 0.0..1.0,
        agent_results: [%{agent: :medication_agent, weight: 1.5, result: %{...}}, ...],
        scores: %{entailment: 2.5, contradiction: 0.0, neutral: 1.3}
      }

  ## Examples

      iex> Consensus.verify("HbA1c is 7.2%", %{source_index: %{labs: []}})
      %{verdict: :neutral, confidence: 0.5, ...}

  """
  @spec verify(String.t(), map(), keyword()) :: consensus_result()
  def verify(claim, context, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    agents = Keyword.get(opts, :agents, @agents)

    # Run all agents in parallel
    agent_results =
      agents
      |> Task.async_stream(
        fn agent ->
          result = agent.verify(claim, context)
          %{agent: agent.name(), weight: agent.weight(), result: result}
        end,
        timeout: timeout,
        max_concurrency: length(agents),
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, result} -> [result]
        {:exit, _reason} -> []
      end)

    # Calculate weighted scores
    scores = calculate_weighted_scores(agent_results)

    # Determine final verdict using Medlum-owned rules
    verdict = determine_verdict(scores)

    # Calculate overall confidence
    confidence = calculate_confidence(scores)

    %{
      verdict: verdict,
      confidence: confidence,
      agent_results: agent_results,
      scores: scores
    }
  end

  @doc """
  Alias for `verify/3` for API consistency with Verifier.

  ## Examples

      iex> Consensus.verify_claim("claim", %{}, [])
      %{verdict: :neutral, ...}

  """
  @spec verify_claim(String.t(), map(), keyword()) :: consensus_result()
  def verify_claim(claim, context, opts \\ []) do
    verify(claim, context, opts)
  end

  @doc """
  Get the list of default agents.

  ## Examples

      iex> agents = Consensus.agents()
      iex> length(agents)
      5

  """
  @spec agents() :: [module()]
  def agents, do: @agents

  @doc """
  Calculate total weight of all agents.

  ## Examples

      iex> Consensus.total_weight()
      5.5

  """
  @spec total_weight() :: float()
  def total_weight do
    Enum.reduce(@agents, 0.0, fn agent, acc -> acc + agent.weight() end)
  end

  # Calculate weighted scores for each verdict type
  defp calculate_weighted_scores(agent_results) do
    initial = %{entailment: 0.0, contradiction: 0.0, neutral: 0.0}

    Enum.reduce(agent_results, initial, fn %{weight: weight, result: result}, acc ->
      verdict = result.verdict
      confidence = result.confidence || 0.5
      score = weight * confidence

      Map.update!(acc, verdict, &(&1 + score))
    end)
  end

  # Determine final verdict using Medlum-owned aggregation rules
  defp determine_verdict(scores) do
    cond do
      # Contradiction precedence: if contradiction score is significant
      # relative to entailment (> 50% of entailment score)
      scores.contradiction > 0 and scores.contradiction > scores.entailment * 0.5 ->
        :contradiction

      # Entailment requires entailment_score > neutral_score
      scores.entailment > scores.neutral ->
        :entailment

      # Neutral is the default
      true ->
        :neutral
    end
  end

  # Calculate overall confidence as ratio of winning score to total
  defp calculate_confidence(scores) do
    total = scores.entailment + scores.contradiction + scores.neutral

    if total == 0 do
      0.5
    else
      max_score = Enum.max([scores.entailment, scores.contradiction, scores.neutral])
      Float.round(max_score / total, 3)
    end
  end
end
