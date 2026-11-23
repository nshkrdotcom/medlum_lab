defmodule MedlumLlm.CVL.Agent do
  @moduledoc """
  Behaviour for CVL verification agents.

  Each agent specializes in verifying a specific aspect of clinical claims:
  - MedicationAgent: Drug names, doses, frequencies (RxNorm)
  - LabAgent: Lab values, reference ranges (LOINC)
  - OntologyAgent: Diagnosis codes, terminology (SNOMED-CT, ICD-10)
  - TemporalAgent: Timeline consistency
  - DifferentialAgent: Symptom-diagnosis mapping

  ## Agent Result Format

      %{
        verdict: :entailment | :contradiction | :neutral,
        confidence: 0.0..1.0,
        explanations: ["Explanation 1", ...],
        evidence: [%{doc_id: "doc-1", snippet: "...", entity_type: :medication, entity: %{...}}, ...],
        sub_verdicts: [{:entailment, "specific claim"}, ...]
      }

  ## Consensus Weights

  Weights determine agent influence in consensus:
  - Medication: 1.5 (highest - safety critical)
  - Lab: 1.2
  - Ontology: 1.0
  - Temporal: 0.8 (often ambiguous)
  - Differential: 1.0

  ## Source Grounding

  CVL's purpose is hallucination detection, so verification must be **source-grounded**:

  - **ENTAILMENT**: Claim is supported by source documents (must include evidence).
  - **CONTRADICTION**: Claim conflicts with source documents or is clearly invalid
    (e.g., physiologically impossible, unknown medication).
  - **NEUTRAL**: Cannot be verified from available evidence (still "needs review" in Medlum UX).

  Agents should prefer `:neutral` when evidence is insufficient rather than
  assuming `:entailment` based solely on ontology lookups.

  """

  @type verdict :: :entailment | :contradiction | :neutral
  @type sub_verdict :: {verdict(), String.t()}
  @type evidence :: %{
          optional(:doc_id) => String.t(),
          optional(:snippet) => String.t(),
          optional(:entity_type) => atom(),
          optional(:entity) => map(),
          optional(:note) => String.t()
        }
  @type result :: %{
          verdict: verdict(),
          confidence: float(),
          explanations: [String.t()],
          evidence: [evidence()],
          sub_verdicts: [sub_verdict()]
        }

  @type context :: %{
          optional(:documents) => [String.t() | map()],
          optional(:source_index) => map(),
          optional(:current_medications) => [map()],
          optional(:conditions) => [map()],
          optional(:demographics) => map(),
          optional(:chief_complaint) => String.t(),
          optional(:diagnoses) => [map()],
          optional(:treatments) => [map()],
          optional(:document_dates) => [Date.t()]
        }

  @doc "Returns the agent's unique name."
  @callback name() :: atom()

  @doc "Returns the agent's weight for consensus voting."
  @callback weight() :: float()

  @doc "Verify a claim against context, returning verdict and explanations."
  @callback verify(claim :: String.t(), context :: context()) :: result()

  @doc """
  Aggregate multiple sub-verdicts into a single result.

  Default implementation:
  - CONTRADICTION if any sub-verdict is contradiction
  - ENTAILMENT if majority are entailment
  - NEUTRAL otherwise
  """
  @spec aggregate_verdicts([sub_verdict()]) :: result()
  def aggregate_verdicts(verdicts) when is_list(verdicts) do
    if Enum.empty?(verdicts) do
      %{
        verdict: :neutral,
        confidence: 0.0,
        explanations: ["No claims to verify"],
        evidence: [],
        sub_verdicts: []
      }
    else
      counts = count_verdicts(verdicts)
      total = length(verdicts)

      {verdict, confidence} =
        cond do
          counts.contradiction > 0 ->
            {:contradiction, counts.contradiction / total}

          counts.entailment > counts.neutral ->
            {:entailment, counts.entailment / total}

          true ->
            {:neutral, counts.neutral / total}
        end

      explanations = Enum.map(verdicts, fn {_, explanation} -> explanation end)

      %{
        verdict: verdict,
        confidence: confidence,
        explanations: explanations,
        evidence: [],
        sub_verdicts: verdicts
      }
    end
  end

  defp count_verdicts(verdicts) do
    Enum.reduce(verdicts, %{entailment: 0, contradiction: 0, neutral: 0}, fn {v, _}, acc ->
      Map.update!(acc, v, &(&1 + 1))
    end)
  end
end
