defmodule MedlumLlm.Labeling.LabelBuilder do
  @moduledoc """
  Builder functions for medical labels.

  Provides factory functions to construct `LabelingIR.Label` structs with
  properly structured values for CVL annotation workflows.

  ## Label Types

  - **NLI Labels** - Human annotations with NLI verdicts, confidence, and reasoning
  - **Agent Labels** - Automated CVL agent verdicts with evidence and ontology codes

  ## Example

      alias MedlumLlm.Labeling.{LabelBuilder, NLI, CVL}

      # Build human NLI label
      label = LabelBuilder.build_nli_label(%{
        assignment_id: "assign_001",
        sample_id: "cvl_abc123",
        queue_id: "cvl_nli_queue",
        tenant_id: "medlum",
        user_id: "annotator_alice",
        verdict: :contradiction,
        time_spent_ms: 45_000,
        confidence: 5,
        reasoning: "Dose mismatch"
      })

      # Build agent label
      agent_verdict = %{
        verdict: :contradiction,
        confidence: 0.92,
        evidence: ["Dose mismatch: 500mg vs 1000mg"],
        ontology_codes: ["861004"]
      }

      agent_label = LabelBuilder.build_agent_label(
        :medication,
        agent_verdict,
        assignment_id: "assign_001",
        sample_id: "cvl_abc123",
        queue_id: "cvl_agent_queue",
        tenant_id: "medlum",
        agent_id: "medication_agent_v1",
        time_spent_ms: 150
      )

  """

  alias LabelingIR.Label
  alias MedlumLlm.Labeling.{NLI, CVL}

  @doc """
  Builds an NLI label from human annotation.

  Creates a `LabelingIR.Label` with values structured for NLI classification.

  ## Required params map keys

  - `:assignment_id` - Parent assignment ID
  - `:sample_id` - Labeled sample ID
  - `:queue_id` - Labeling queue ID
  - `:tenant_id` - Tenant identifier
  - `:user_id` - Annotator's user ID
  - `:verdict` - NLI verdict atom (`:entailment`, `:contradiction`, `:neutral`)
  - `:time_spent_ms` - Time spent labeling in milliseconds

  ## Optional params map keys

  - `:namespace` - Namespace for sub-tenant grouping
  - `:confidence` - Labeler confidence (1-5 scale)
  - `:reasoning` - Free-text reasoning explanation
  - `:evidence_spans` - Quoted evidence from premise
  - `:difficulty` - Subjective difficulty ("easy", "medium", "hard")
  - `:notes` - Additional free-form notes
  - `:metadata` - Additional metadata to merge

  ## Examples

      iex> label = MedlumLlm.Labeling.LabelBuilder.build_nli_label(%{
      ...>   assignment_id: "assign_001",
      ...>   sample_id: "sample_001",
      ...>   queue_id: "cvl_queue",
      ...>   tenant_id: "medlum",
      ...>   user_id: "alice",
      ...>   verdict: :contradiction,
      ...>   time_spent_ms: 30_000,
      ...>   confidence: 4,
      ...>   reasoning: "Medication dose differs"
      ...> })
      iex> label.values["nli_label"]
      "CONTRADICTION"
      iex> label.values["confidence"]
      4

  """
  @spec build_nli_label(map()) :: Label.t()
  def build_nli_label(params) when is_map(params) do
    id = generate_label_id()
    assignment_id = Map.fetch!(params, :assignment_id)
    sample_id = Map.fetch!(params, :sample_id)
    queue_id = Map.fetch!(params, :queue_id)
    tenant_id = Map.fetch!(params, :tenant_id)
    user_id = Map.fetch!(params, :user_id)
    verdict = Map.fetch!(params, :verdict)
    time_spent_ms = Map.fetch!(params, :time_spent_ms)

    namespace = Map.get(params, :namespace)
    confidence = Map.get(params, :confidence)
    reasoning = Map.get(params, :reasoning)
    evidence_spans = Map.get(params, :evidence_spans)
    difficulty = Map.get(params, :difficulty)
    notes = Map.get(params, :notes)
    extra_metadata = Map.get(params, :metadata, %{})

    values =
      %{
        "nli_label" => NLI.verdict_to_label(verdict),
        "confidence" => confidence,
        "reasoning" => reasoning,
        "evidence_spans" => evidence_spans,
        "difficulty" => difficulty
      }
      |> reject_nils()

    %Label{
      id: id,
      assignment_id: assignment_id,
      sample_id: sample_id,
      queue_id: queue_id,
      tenant_id: tenant_id,
      namespace: namespace,
      user_id: user_id,
      values: values,
      notes: notes,
      time_spent_ms: time_spent_ms,
      created_at: DateTime.utc_now(),
      lineage_ref: nil,
      metadata: extra_metadata
    }
  end

  @doc """
  Builds an agent verdict label.

  Creates a `LabelingIR.Label` from a CVL agent's verification result.
  The `user_id` is set to `"agent:<agent_id>"` to distinguish agent labels
  from human annotations.

  ## Parameters

  - `agent_type` - CVL agent type atom (`:medication`, `:lab`, etc.)
  - `verdict` - Agent verdict map with `:verdict`, `:confidence`, `:evidence`, `:ontology_codes`

  ## Required keyword options

  - `:assignment_id` - Parent assignment ID
  - `:sample_id` - Labeled sample ID
  - `:queue_id` - Labeling queue ID
  - `:tenant_id` - Tenant identifier
  - `:agent_id` - Unique agent identifier (used in user_id)
  - `:time_spent_ms` - Processing time in milliseconds

  ## Optional keyword options

  - `:namespace` - Namespace for sub-tenant grouping
  - `:metadata` - Additional metadata to merge

  ## Examples

      iex> verdict = %{
      ...>   verdict: :contradiction,
      ...>   confidence: 0.92,
      ...>   evidence: ["Dose mismatch"],
      ...>   ontology_codes: ["861004"]
      ...> }
      iex> label = MedlumLlm.Labeling.LabelBuilder.build_agent_label(
      ...>   :medication,
      ...>   verdict,
      ...>   assignment_id: "assign_001",
      ...>   sample_id: "sample_001",
      ...>   queue_id: "agent_queue",
      ...>   tenant_id: "medlum",
      ...>   agent_id: "medication_agent_v1",
      ...>   time_spent_ms: 150
      ...> )
      iex> label.user_id
      "agent:medication_agent_v1"
      iex> label.values["agent_type"]
      "medication"
      iex> label.metadata["is_agent_label"]
      true

  """
  @spec build_agent_label(CVL.agent_type(), CVL.agent_verdict(), keyword()) :: Label.t()
  def build_agent_label(agent_type, verdict, opts) when is_atom(agent_type) and is_map(verdict) do
    id = generate_label_id()
    assignment_id = Keyword.fetch!(opts, :assignment_id)
    sample_id = Keyword.fetch!(opts, :sample_id)
    queue_id = Keyword.fetch!(opts, :queue_id)
    tenant_id = Keyword.fetch!(opts, :tenant_id)
    agent_id = Keyword.fetch!(opts, :agent_id)
    time_spent_ms = Keyword.fetch!(opts, :time_spent_ms)

    namespace = Keyword.get(opts, :namespace)
    extra_metadata = Keyword.get(opts, :metadata, %{})

    values = %{
      "agent_type" => Atom.to_string(agent_type),
      "verdict" => NLI.verdict_to_label(verdict.verdict),
      "confidence" => verdict.confidence,
      "evidence" => verdict.evidence,
      "ontology_codes" => verdict.ontology_codes
    }

    metadata =
      Map.merge(
        %{"is_agent_label" => true, "agent_version" => agent_id},
        extra_metadata
      )

    %Label{
      id: id,
      assignment_id: assignment_id,
      sample_id: sample_id,
      queue_id: queue_id,
      tenant_id: tenant_id,
      namespace: namespace,
      user_id: "agent:#{agent_id}",
      values: values,
      notes: nil,
      time_spent_ms: time_spent_ms,
      created_at: DateTime.utc_now(),
      lineage_ref: nil,
      metadata: metadata
    }
  end

  @doc """
  Builds a consensus label from multiple agent verdicts.

  Creates a `LabelingIR.Label` representing the aggregated consensus from
  multiple CVL agents.

  ## Parameters

  - `consensus_result` - Consensus result map with agent verdicts and consensus verdict

  ## Required keyword options

  - `:assignment_id` - Parent assignment ID
  - `:sample_id` - Labeled sample ID
  - `:queue_id` - Labeling queue ID
  - `:tenant_id` - Tenant identifier
  - `:time_spent_ms` - Total processing time in milliseconds

  ## Optional keyword options

  - `:namespace` - Namespace for sub-tenant grouping
  - `:metadata` - Additional metadata to merge

  ## Examples

      iex> consensus = %{
      ...>   agent_verdicts: %{
      ...>     medication: %{verdict: :contradiction, confidence: 0.9, evidence: [], ontology_codes: []},
      ...>     lab: %{verdict: :entailment, confidence: 0.8, evidence: [], ontology_codes: []}
      ...>   },
      ...>   consensus_verdict: :contradiction,
      ...>   consensus_method: :weighted_vote,
      ...>   dissent_count: 1
      ...> }
      iex> label = MedlumLlm.Labeling.LabelBuilder.build_consensus_label(
      ...>   consensus,
      ...>   assignment_id: "assign_001",
      ...>   sample_id: "sample_001",
      ...>   queue_id: "consensus_queue",
      ...>   tenant_id: "medlum",
      ...>   time_spent_ms: 500
      ...> )
      iex> label.user_id
      "agent:cvl_consensus"
      iex> label.values["consensus_verdict"]
      "CONTRADICTION"

  """
  @spec build_consensus_label(CVL.consensus_result(), keyword()) :: Label.t()
  def build_consensus_label(consensus_result, opts) when is_map(consensus_result) do
    id = generate_label_id()
    assignment_id = Keyword.fetch!(opts, :assignment_id)
    sample_id = Keyword.fetch!(opts, :sample_id)
    queue_id = Keyword.fetch!(opts, :queue_id)
    tenant_id = Keyword.fetch!(opts, :tenant_id)
    time_spent_ms = Keyword.fetch!(opts, :time_spent_ms)

    namespace = Keyword.get(opts, :namespace)
    extra_metadata = Keyword.get(opts, :metadata, %{})

    agent_verdicts_serialized =
      Map.new(consensus_result.agent_verdicts, fn {agent_type, verdict} ->
        {Atom.to_string(agent_type), serialize_agent_verdict(verdict)}
      end)

    values = %{
      "consensus_verdict" => NLI.verdict_to_label(consensus_result.consensus_verdict),
      "consensus_method" => Atom.to_string(consensus_result.consensus_method),
      "dissent_count" => consensus_result.dissent_count,
      "agent_verdicts" => agent_verdicts_serialized
    }

    metadata =
      Map.merge(
        %{"is_consensus_label" => true},
        extra_metadata
      )

    %Label{
      id: id,
      assignment_id: assignment_id,
      sample_id: sample_id,
      queue_id: queue_id,
      tenant_id: tenant_id,
      namespace: namespace,
      user_id: "agent:cvl_consensus",
      values: values,
      notes: nil,
      time_spent_ms: time_spent_ms,
      created_at: DateTime.utc_now(),
      lineage_ref: nil,
      metadata: metadata
    }
  end

  @doc """
  Generates a unique label ID with the `lbl_` prefix.

  ## Examples

      iex> id = MedlumLlm.Labeling.LabelBuilder.generate_label_id()
      iex> String.starts_with?(id, "lbl_")
      true
      iex> String.length(id)
      28

  """
  @spec generate_label_id() :: String.t()
  def generate_label_id do
    "lbl_" <> (:crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower))
  end

  # Private helpers

  defp serialize_agent_verdict(verdict) do
    %{
      "verdict" => NLI.verdict_to_label(verdict.verdict),
      "confidence" => verdict.confidence,
      "evidence" => verdict.evidence,
      "ontology_codes" => verdict.ontology_codes
    }
  end

  defp reject_nils(map) do
    Map.reject(map, fn {_, v} -> is_nil(v) end)
  end
end
