defmodule MedlumLlm.Metrics.CVL do
  @moduledoc """
  CVL-specific metrics for the Clinical Verification Layer.

  The Clinical Verification Layer (CVL) is a multi-agent system for detecting
  hallucinations in medical AI outputs. This module provides metrics recording
  and querying for CVL operations.

  ## Agents

  CVL uses five specialized agents for verification consensus:

  - `:medication` - Drug name, dose, frequency validation (RxNorm)
  - `:lab` - Lab values and reference ranges (LOINC)
  - `:ontology` - SNOMED-CT/ICD-10 consistency
  - `:temporal` - Timeline and progression logic
  - `:differential` - Symptom-diagnosis mapping

  ## Verdicts

  Each verification produces one of three verdicts:

  - `:entailment` - Claim is supported by evidence
  - `:contradiction` - Claim conflicts with evidence
  - `:neutral` - Claim cannot be verified from evidence

  ## Metrics

  This module records the following metrics:

  - `medlum_cvl_verdict_count` - Counter by verdict type
  - `medlum_cvl_verify_duration_ms` - Histogram of verification latency
  - `medlum_cvl_confidence` - Histogram of confidence scores
  - `medlum_cvl_agent_verdict_count` - Counter by agent and verdict
  - `medlum_cvl_agent_duration_ms` - Histogram of per-agent latency
  - `medlum_cvl_consensus_duration_ms` - Histogram of consensus latency
  - `medlum_cvl_agreement_count` - Gauge of agents in agreement
  - `medlum_cvl_agreement_rate` - Histogram of agreement rate (0.0-1.0)
  - `medlum_cvl_detection_outcome` - Counter by outcome (TP/FP/TN/FN)

  ## Usage

      # Record a verification result
      MedlumLlm.Metrics.CVL.record_verification(:contradiction, 150.5,
        verifier_type: :ensemble,
        confidence: 0.92,
        run_id: "run_123"
      )

      # Record individual agent verdict
      MedlumLlm.Metrics.CVL.record_agent_verdict(:medication, :entailment, 45.2,
        confidence: 0.88
      )

      # Record consensus
      MedlumLlm.Metrics.CVL.record_consensus(:entailment, 4, 180.0, run_id: "run_123")

      # Record hallucination detection outcome
      MedlumLlm.Metrics.CVL.record_hallucination_detection(true, true,
        verifier_type: :ensemble
      )
  """

  alias MetricsEx

  @agents [:medication, :lab, :ontology, :temporal, :differential]
  @verdicts [:entailment, :contradiction, :neutral]

  @doc """
  Returns the list of CVL agent names.
  """
  @spec agents() :: list(atom())
  def agents, do: @agents

  @doc """
  Returns the list of possible verdict values.
  """
  @spec verdicts() :: list(atom())
  def verdicts, do: @verdicts

  @doc """
  Record CVL verification result.

  Records the overall verification outcome including verdict, duration,
  and optional confidence score.

  ## Parameters

    - `verdict` - The verification verdict: `:entailment`, `:contradiction`, or `:neutral`
    - `duration_ms` - Verification duration in milliseconds
    - `opts` - Options:
      - `:verifier_type` - Type of verifier (`:ensemble` or `:single_agent`, default: `:ensemble`)
      - `:confidence` - Confidence score (0.0-1.0)
      - `:run_id` - Evaluation run ID for correlation

  ## Examples

      iex> MedlumLlm.Metrics.CVL.record_verification(:contradiction, 150.5,
      ...>   verifier_type: :ensemble,
      ...>   confidence: 0.92
      ...> )
      :ok
  """
  @spec record_verification(atom(), number(), keyword()) :: :ok
  def record_verification(verdict, duration_ms, opts \\ [])
      when verdict in @verdicts and is_number(duration_ms) do
    verifier_type = Keyword.get(opts, :verifier_type, :ensemble)
    confidence = Keyword.get(opts, :confidence)
    run_id = Keyword.get(opts, :run_id)

    # Record verification duration histogram
    MetricsEx.histogram(:medlum_cvl_verify_duration_ms, duration_ms,
      tags: %{
        verifier_type: verifier_type,
        verdict: verdict
      }
    )

    # Record verdict count
    tags = %{
      verdict: verdict,
      verifier_type: verifier_type
    }

    tags = if run_id, do: Map.put(tags, :run_id, run_id), else: tags

    MetricsEx.increment(:medlum_cvl_verdict_count, 1, tags: tags)

    # Record confidence if provided
    if confidence do
      MetricsEx.histogram(:medlum_cvl_confidence, confidence,
        tags: %{
          verdict: verdict,
          verifier_type: verifier_type
        }
      )
    end

    :ok
  end

  @doc """
  Record individual CVL agent verdict.

  Records the verdict from a single CVL agent, including duration
  and optional confidence score.

  ## Parameters

    - `agent` - The agent name: `:medication`, `:lab`, `:ontology`, `:temporal`, or `:differential`
    - `verdict` - The verdict: `:entailment`, `:contradiction`, or `:neutral`
    - `duration_ms` - Agent processing duration in milliseconds
    - `opts` - Options:
      - `:confidence` - Confidence score (0.0-1.0)
      - `:run_id` - Evaluation run ID for correlation

  ## Examples

      iex> MedlumLlm.Metrics.CVL.record_agent_verdict(:medication, :entailment, 45.2,
      ...>   confidence: 0.88
      ...> )
      :ok
  """
  @spec record_agent_verdict(atom(), atom(), number(), keyword()) :: :ok
  def record_agent_verdict(agent, verdict, duration_ms, opts \\ [])
      when agent in @agents and verdict in @verdicts and is_number(duration_ms) do
    confidence = Keyword.get(opts, :confidence)

    # Record agent duration histogram
    MetricsEx.histogram(:medlum_cvl_agent_duration_ms, duration_ms,
      tags: %{
        agent: agent,
        verdict: verdict
      }
    )

    # Record agent verdict count
    MetricsEx.increment(:medlum_cvl_agent_verdict_count, 1,
      tags: %{
        agent: agent,
        verdict: verdict
      }
    )

    # Record agent confidence if provided
    if confidence do
      MetricsEx.histogram(:medlum_cvl_agent_confidence, confidence,
        tags: %{
          agent: agent
        }
      )
    end

    :ok
  end

  @doc """
  Record consensus result from all agents.

  Records the final consensus verdict along with the number of
  agents that agreed with the final decision.

  ## Parameters

    - `final_verdict` - The consensus verdict: `:entailment`, `:contradiction`, or `:neutral`
    - `agreement_count` - Number of agents that agreed (0-5)
    - `duration_ms` - Total consensus duration in milliseconds
    - `opts` - Options:
      - `:run_id` - Evaluation run ID for correlation

  ## Examples

      iex> MedlumLlm.Metrics.CVL.record_consensus(:entailment, 4, 180.0, run_id: "run_123")
      :ok
  """
  @spec record_consensus(atom(), integer(), number(), keyword()) :: :ok
  def record_consensus(final_verdict, agreement_count, duration_ms, opts \\ [])
      when final_verdict in @verdicts and
             is_integer(agreement_count) and
             agreement_count >= 0 and
             is_number(duration_ms) do
    _run_id = Keyword.get(opts, :run_id)

    # Record consensus duration histogram
    MetricsEx.histogram(:medlum_cvl_consensus_duration_ms, duration_ms,
      tags: %{
        verdict: final_verdict
      }
    )

    # Record agreement count gauge
    MetricsEx.gauge(:medlum_cvl_agreement_count, agreement_count,
      tags: %{
        verdict: final_verdict
      }
    )

    # Agreement rate out of 5 agents
    agreement_rate = agreement_count / length(@agents)

    MetricsEx.histogram(:medlum_cvl_agreement_rate, agreement_rate, tags: %{})

    :ok
  end

  @doc """
  Record hallucination detection outcome.

  Tracks the confusion matrix outcomes for CVL's hallucination detection:

  - True positive (TP): CVL flagged and was hallucination
  - False positive (FP): CVL flagged but was not hallucination
  - True negative (TN): CVL did not flag and was not hallucination
  - False negative (FN): CVL did not flag but was hallucination

  ## Parameters

    - `cvl_flagged` - Whether CVL flagged as potential hallucination
    - `was_hallucination` - Ground truth: whether it was actually a hallucination
    - `opts` - Options:
      - `:verifier_type` - Type of verifier (`:ensemble` or `:single_agent`, default: `:ensemble`)
      - `:run_id` - Evaluation run ID for correlation

  ## Examples

      iex> MedlumLlm.Metrics.CVL.record_hallucination_detection(true, true,
      ...>   verifier_type: :ensemble
      ...> )
      :ok

      iex> MedlumLlm.Metrics.CVL.record_hallucination_detection(false, true,
      ...>   verifier_type: :single_agent
      ...> )
      :ok
  """
  @spec record_hallucination_detection(boolean(), boolean(), keyword()) :: :ok
  def record_hallucination_detection(cvl_flagged, was_hallucination, opts \\ [])
      when is_boolean(cvl_flagged) and is_boolean(was_hallucination) do
    verifier_type = Keyword.get(opts, :verifier_type, :ensemble)

    outcome =
      case {cvl_flagged, was_hallucination} do
        {true, true} -> :true_positive
        {true, false} -> :false_positive
        {false, true} -> :false_negative
        {false, false} -> :true_negative
      end

    MetricsEx.increment(:medlum_cvl_detection_outcome, 1,
      tags: %{
        outcome: outcome,
        verifier_type: verifier_type
      }
    )

    :ok
  end
end
