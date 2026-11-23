defmodule MedlumLlm.Labeling.CVL do
  @moduledoc """
  Types and validation for Clinical Verification Layer (CVL) multi-agent system.

  CVL uses 5 specialized verification agents to detect hallucinations in
  LLM-generated clinical summaries:

  1. **Medication Agent** - Verifies drug names, doses, frequencies (RxNorm)
  2. **Lab Agent** - Validates lab values and reference ranges (LOINC)
  3. **Ontology Agent** - Checks SNOMED-CT/ICD-10 consistency
  4. **Temporal Agent** - Validates timeline and progression logic
  5. **Differential Agent** - Verifies symptom-diagnosis mapping

  Each agent produces a verdict that is aggregated into a consensus result.

  ## Example

      iex> MedlumLlm.Labeling.CVL.agent_types()
      [:medication, :lab, :ontology, :temporal, :differential]

      iex> agent_verdict = %{
      ...>   verdict: :contradiction,
      ...>   confidence: 0.92,
      ...>   evidence: ["Dose mismatch: 500mg vs 1000mg"],
      ...>   ontology_codes: ["861004"]
      ...> }
      iex> {:ok, _validated} = MedlumLlm.Labeling.CVL.validate_agent_verdict(agent_verdict)

  """

  alias MedlumLlm.Labeling.NLI

  @typedoc """
  CVL agent type identifier.

  Each agent specializes in a specific aspect of clinical verification:
  - `:medication` - Drug verification using RxNorm
  - `:lab` - Lab value verification using LOINC
  - `:ontology` - Clinical terminology using SNOMED-CT/ICD-10
  - `:temporal` - Timeline and date logic
  - `:differential` - Diagnosis-symptom mapping
  """
  @type agent_type :: :medication | :lab | :ontology | :temporal | :differential

  @typedoc """
  Individual agent verification result.

  Contains the agent's verdict, confidence score, supporting evidence,
  and relevant ontology codes.
  """
  @type agent_verdict :: %{
          verdict: NLI.verdict(),
          confidence: float(),
          evidence: [String.t()],
          ontology_codes: [String.t()]
        }

  @typedoc """
  Method used to aggregate agent verdicts into consensus.

  - `:majority_vote` - Simple majority wins
  - `:weighted_vote` - Votes weighted by agent confidence
  - `:unanimous` - All agents must agree
  """
  @type consensus_method :: :majority_vote | :weighted_vote | :unanimous

  @typedoc """
  Aggregated consensus result from all CVL agents.

  Contains individual agent verdicts, the final consensus verdict,
  the method used for aggregation, and count of dissenting agents.
  """
  @type consensus_result :: %{
          agent_verdicts: %{agent_type() => agent_verdict()},
          consensus_verdict: NLI.verdict(),
          consensus_method: consensus_method(),
          dissent_count: non_neg_integer()
        }

  @agent_types [:medication, :lab, :ontology, :temporal, :differential]
  @consensus_methods [:majority_vote, :weighted_vote, :unanimous]

  @doc """
  Returns the list of all CVL agent types.

  ## Examples

      iex> MedlumLlm.Labeling.CVL.agent_types()
      [:medication, :lab, :ontology, :temporal, :differential]

  """
  @spec agent_types() :: [agent_type()]
  def agent_types, do: @agent_types

  @doc """
  Checks if an atom is a valid CVL agent type.

  ## Examples

      iex> MedlumLlm.Labeling.CVL.valid_agent_type?(:medication)
      true

      iex> MedlumLlm.Labeling.CVL.valid_agent_type?(:unknown)
      false

  """
  @spec valid_agent_type?(atom()) :: boolean()
  def valid_agent_type?(agent_type) when is_atom(agent_type), do: agent_type in @agent_types
  def valid_agent_type?(_), do: false

  @doc """
  Returns the list of valid consensus methods.

  ## Examples

      iex> MedlumLlm.Labeling.CVL.consensus_methods()
      [:majority_vote, :weighted_vote, :unanimous]

  """
  @spec consensus_methods() :: [consensus_method()]
  def consensus_methods, do: @consensus_methods

  @doc """
  Checks if an atom is a valid consensus method.

  ## Examples

      iex> MedlumLlm.Labeling.CVL.valid_consensus_method?(:majority_vote)
      true

      iex> MedlumLlm.Labeling.CVL.valid_consensus_method?(:random)
      false

  """
  @spec valid_consensus_method?(atom()) :: boolean()
  def valid_consensus_method?(method) when is_atom(method), do: method in @consensus_methods
  def valid_consensus_method?(_), do: false

  @doc """
  Validates an agent verdict map.

  Checks that all required keys are present and values have correct types:
  - `verdict` must be a valid NLI verdict atom
  - `confidence` must be a float between 0.0 and 1.0
  - `evidence` must be a list of strings
  - `ontology_codes` must be a list of strings

  ## Examples

      iex> verdict = %{
      ...>   verdict: :contradiction,
      ...>   confidence: 0.92,
      ...>   evidence: ["Dose mismatch"],
      ...>   ontology_codes: ["861004"]
      ...> }
      iex> {:ok, validated} = MedlumLlm.Labeling.CVL.validate_agent_verdict(verdict)
      iex> validated.verdict
      :contradiction

      iex> MedlumLlm.Labeling.CVL.validate_agent_verdict(%{verdict: :invalid})
      {:error, {:invalid_verdict, :invalid}}

  """
  @spec validate_agent_verdict(map()) :: {:ok, agent_verdict()} | {:error, term()}
  def validate_agent_verdict(map) when is_map(map) do
    with {:ok, verdict} <- validate_verdict_field(map),
         {:ok, confidence} <- validate_confidence_field(map),
         {:ok, evidence} <- validate_evidence_field(map),
         {:ok, ontology_codes} <- validate_ontology_codes_field(map) do
      {:ok,
       %{
         verdict: verdict,
         confidence: confidence,
         evidence: evidence,
         ontology_codes: ontology_codes
       }}
    end
  end

  def validate_agent_verdict(_), do: {:error, :not_a_map}

  @doc """
  Validates an agent verdict map, raising on invalid input.

  ## Examples

      iex> verdict = %{
      ...>   verdict: :entailment,
      ...>   confidence: 0.85,
      ...>   evidence: [],
      ...>   ontology_codes: []
      ...> }
      iex> validated = MedlumLlm.Labeling.CVL.validate_agent_verdict!(verdict)
      iex> validated.verdict
      :entailment

  """
  @spec validate_agent_verdict!(map()) :: agent_verdict()
  def validate_agent_verdict!(map) do
    case validate_agent_verdict(map) do
      {:ok, verdict} -> verdict
      {:error, reason} -> raise ArgumentError, "Invalid agent verdict: #{inspect(reason)}"
    end
  end

  @doc """
  Validates a consensus result map.

  Checks that all required keys are present and values have correct types.

  ## Examples

      iex> result = %{
      ...>   agent_verdicts: %{medication: %{verdict: :contradiction, confidence: 0.9, evidence: [], ontology_codes: []}},
      ...>   consensus_verdict: :contradiction,
      ...>   consensus_method: :majority_vote,
      ...>   dissent_count: 0
      ...> }
      iex> {:ok, _validated} = MedlumLlm.Labeling.CVL.validate_consensus_result(result)

  """
  @spec validate_consensus_result(map()) :: {:ok, consensus_result()} | {:error, term()}
  def validate_consensus_result(map) when is_map(map) do
    with {:ok, agent_verdicts} <- validate_agent_verdicts_map(map),
         {:ok, consensus_verdict} <- validate_consensus_verdict_field(map),
         {:ok, consensus_method} <- validate_consensus_method_field(map),
         {:ok, dissent_count} <- validate_dissent_count_field(map) do
      {:ok,
       %{
         agent_verdicts: agent_verdicts,
         consensus_verdict: consensus_verdict,
         consensus_method: consensus_method,
         dissent_count: dissent_count
       }}
    end
  end

  def validate_consensus_result(_), do: {:error, :not_a_map}

  # Private validation helpers

  defp validate_verdict_field(map) do
    case Map.fetch(map, :verdict) do
      {:ok, verdict} when is_atom(verdict) ->
        if NLI.valid_verdict?(verdict) do
          {:ok, verdict}
        else
          {:error, {:invalid_verdict, verdict}}
        end

      {:ok, other} ->
        {:error, {:invalid_verdict_type, other}}

      :error ->
        {:error, :missing_verdict}
    end
  end

  defp validate_confidence_field(map) do
    case Map.fetch(map, :confidence) do
      {:ok, confidence} when is_float(confidence) or is_integer(confidence) ->
        conf = confidence * 1.0

        if conf >= 0.0 and conf <= 1.0 do
          {:ok, conf}
        else
          {:error, {:confidence_out_of_range, confidence}}
        end

      {:ok, other} ->
        {:error, {:invalid_confidence_type, other}}

      :error ->
        {:error, :missing_confidence}
    end
  end

  defp validate_evidence_field(map) do
    case Map.fetch(map, :evidence) do
      {:ok, evidence} when is_list(evidence) ->
        if Enum.all?(evidence, &is_binary/1) do
          {:ok, evidence}
        else
          {:error, :evidence_not_string_list}
        end

      {:ok, other} ->
        {:error, {:invalid_evidence_type, other}}

      :error ->
        {:error, :missing_evidence}
    end
  end

  defp validate_ontology_codes_field(map) do
    case Map.fetch(map, :ontology_codes) do
      {:ok, codes} when is_list(codes) ->
        if Enum.all?(codes, &is_binary/1) do
          {:ok, codes}
        else
          {:error, :ontology_codes_not_string_list}
        end

      {:ok, other} ->
        {:error, {:invalid_ontology_codes_type, other}}

      :error ->
        {:error, :missing_ontology_codes}
    end
  end

  defp validate_agent_verdicts_map(map) do
    case Map.fetch(map, :agent_verdicts) do
      {:ok, verdicts} when is_map(verdicts) ->
        validated =
          Enum.reduce_while(verdicts, {:ok, %{}}, fn {agent_type, verdict}, {:ok, acc} ->
            if valid_agent_type?(agent_type) do
              case validate_agent_verdict(verdict) do
                {:ok, valid_verdict} -> {:cont, {:ok, Map.put(acc, agent_type, valid_verdict)}}
                {:error, reason} -> {:halt, {:error, {:invalid_agent_verdict, agent_type, reason}}}
              end
            else
              {:halt, {:error, {:invalid_agent_type, agent_type}}}
            end
          end)

        validated

      {:ok, other} ->
        {:error, {:invalid_agent_verdicts_type, other}}

      :error ->
        {:error, :missing_agent_verdicts}
    end
  end

  defp validate_consensus_verdict_field(map) do
    case Map.fetch(map, :consensus_verdict) do
      {:ok, verdict} when is_atom(verdict) ->
        if NLI.valid_verdict?(verdict) do
          {:ok, verdict}
        else
          {:error, {:invalid_consensus_verdict, verdict}}
        end

      {:ok, other} ->
        {:error, {:invalid_consensus_verdict_type, other}}

      :error ->
        {:error, :missing_consensus_verdict}
    end
  end

  defp validate_consensus_method_field(map) do
    case Map.fetch(map, :consensus_method) do
      {:ok, method} when is_atom(method) ->
        if valid_consensus_method?(method) do
          {:ok, method}
        else
          {:error, {:invalid_consensus_method, method}}
        end

      {:ok, other} ->
        {:error, {:invalid_consensus_method_type, other}}

      :error ->
        {:error, :missing_consensus_method}
    end
  end

  defp validate_dissent_count_field(map) do
    case Map.fetch(map, :dissent_count) do
      {:ok, count} when is_integer(count) and count >= 0 ->
        {:ok, count}

      {:ok, other} ->
        {:error, {:invalid_dissent_count, other}}

      :error ->
        {:error, :missing_dissent_count}
    end
  end
end
