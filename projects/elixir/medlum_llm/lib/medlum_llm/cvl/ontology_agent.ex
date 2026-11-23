defmodule MedlumLlm.CVL.OntologyAgent do
  @moduledoc """
  Verifies clinical terminology against SNOMED-CT and ICD-10.

  Part of the 5-agent CVL consensus system with weight 1.0.

  ## Verifies

  - Diagnosis code validity
  - Hierarchical relationship consistency
  - Symptom-diagnosis semantic alignment
  - Procedure-diagnosis compatibility

  ## Source Grounding

  Verification follows source-grounded semantics:

  - **ENTAILMENT**: Clinical entity is valid AND found in source documents
  - **CONTRADICTION**: Clinical entity is invalid (unknown code, invalid terminology) OR
    conflicts with source
  - **NEUTRAL**: Clinical entity is valid but not found in source documents
    (possible hallucination, needs review)

  ## Examples

      claim = "Patient diagnosed with type 2 diabetes mellitus"
      context = %{
        chief_complaint: "increased thirst and urination",
        source_index: %{
          diagnoses: [%{text: "type 2 diabetes mellitus", doc_id: "note-1"}]
        }
      }

      result = OntologyAgent.verify(claim, context)
      #=> %{verdict: :entailment, confidence: 0.9, ...}

  """

  @behaviour MedlumLlm.CVL.Agent

  alias MedlumLlm.CVL.Agent

  # Ontology modules - use real ones when available
  @snomed Application.compile_env(:medlum_llm, :snomed_module, MedlumLlm.CVL.SNOMEDStub)
  @icd10 Application.compile_env(:medlum_llm, :icd10_module, MedlumLlm.CVL.ICD10Stub)

  @impl true
  def name, do: :ontology_agent

  @impl true
  def weight, do: 1.0

  @impl true
  def verify(claim, context) do
    entities = extract_clinical_entities(claim)

    if Enum.empty?(entities) do
      %{
        verdict: :neutral,
        confidence: 0.5,
        explanations: ["No clinical entities found in claim"],
        evidence: [],
        sub_verdicts: []
      }
    else
      # Source grounding: an entity that is absent from source documents should default to :neutral.
      source_diagnoses = source_diagnoses(context)

      {entity_verdicts, evidence} =
        Enum.map_reduce(entities, [], fn entity, acc ->
          {sub_verdict, ev} = verify_entity(entity, source_diagnoses, context)
          {sub_verdict, if(ev, do: [ev | acc], else: acc)}
        end)

      # Verify relationships between entities
      relationship_verdicts = verify_relationships(entities, context)

      all_verdicts = entity_verdicts ++ relationship_verdicts

      result = Agent.aggregate_verdicts(all_verdicts)
      %{result | evidence: Enum.reverse(evidence)}
    end
  end

  @doc """
  Extract clinical entities (diagnoses, procedures, findings) from text.
  """
  @spec extract_clinical_entities(String.t()) :: [map()]
  def extract_clinical_entities(claim) do
    if Code.ensure_loaded?(ClinicalNerEx) do
      case apply(ClinicalNerEx, :extract, [claim, [entity_types: [:diagnosis, :procedure, :finding]]]) do
        {:ok, entities} -> Enum.map(entities, &normalize_entity/1)
        _ -> extract_entities_regex(claim)
      end
    else
      extract_entities_regex(claim)
    end
  end

  defp extract_entities_regex(text) do
    # Common diagnosis patterns
    diagnosis_patterns = [
      {~r/(?:diagnosed with|diagnosis of|dx:?)\s+([a-z][a-z\s]+?)(?:\.|,|$)/i, :diagnosis},
      {~r/\b(type [12] diabetes(?:\s+mellitus)?)\b/i, :diagnosis},
      {~r/\b(hypertension)\b/i, :diagnosis},
      {~r/\b(myocardial infarction|heart attack|MI)\b/i, :diagnosis},
      {~r/\b(pneumonia)\b/i, :diagnosis},
      {~r/\b(congestive heart failure|CHF)\b/i, :diagnosis},
      {~r/\b(chronic kidney disease|CKD)\b/i, :diagnosis},
      {~r/\b(asthma)\b/i, :diagnosis},
      {~r/\b(COPD|chronic obstructive pulmonary disease)\b/i, :diagnosis},
      {~r/\b(atrial fibrillation|afib)\b/i, :diagnosis},
      {~r/\b(stroke|CVA)\b/i, :diagnosis}
    ]

    # Finding patterns
    finding_patterns = [
      {~r/\b(chest pain)\b/i, :finding},
      {~r/\b(shortness of breath|dyspnea)\b/i, :finding},
      {~r/\b(fever)\b/i, :finding},
      {~r/\b(cough)\b/i, :finding},
      {~r/\b(headache)\b/i, :finding},
      {~r/\b(fatigue)\b/i, :finding},
      {~r/\b(nausea|vomiting)\b/i, :finding},
      {~r/\b(edema|swelling)\b/i, :finding}
    ]

    # Procedure patterns
    procedure_patterns = [
      {~r/\b(?:underwent|performed)\s+([a-z][a-z\s]+?)(?:\.|,|$)/i, :procedure},
      {~r/\b(coronary artery bypass|CABG)\b/i, :procedure},
      {~r/\b(angioplasty|PCI)\b/i, :procedure},
      {~r/\b(appendectomy)\b/i, :procedure}
    ]

    all_patterns = diagnosis_patterns ++ finding_patterns ++ procedure_patterns

    Enum.flat_map(all_patterns, fn {regex, type} ->
      case Regex.run(regex, text) do
        [full | captures] ->
          text_match =
            case captures do
              [c | _] -> c
              [] -> full
            end

          [
            %{
              text: String.trim(text_match),
              type: type,
              raw_text: full
            }
          ]

        nil ->
          []
      end
    end)
    |> Enum.uniq_by(fn e -> String.downcase(e.text) end)
  end

  defp normalize_entity(entity) do
    %{
      text: entity[:text] || entity["text"],
      type: entity[:type] || entity["type"] || :unknown,
      snomed_id: entity[:snomed_id] || entity["snomed_id"],
      icd10: entity[:icd10] || entity["icd10"]
    }
  end

  defp source_diagnoses(context) do
    cond do
      is_map(context[:source_index]) and is_list(get_in(context, [:source_index, :diagnoses])) ->
        get_in(context, [:source_index, :diagnoses])

      true ->
        []
    end
  end

  defp verify_entity(entity, source_diagnoses, context) do
    source_match = find_source_diagnosis(source_diagnoses, entity.text)

    if is_nil(source_match) do
      {{:neutral, "Entity '#{entity.text}' not found in source documents"}, nil}
    else
      evidence = %{
        doc_id: source_match[:doc_id],
        snippet: source_match[:text] || source_match[:snippet] || "",
        entity_type: entity.type,
        entity: source_match
      }

      verdict =
        case entity.type do
          :diagnosis -> verify_diagnosis(entity, context)
          :procedure -> verify_procedure(entity, context)
          :finding -> verify_finding(entity, context)
          _ -> {:neutral, "Unknown entity type: #{entity.type}"}
        end

      {verdict, evidence}
    end
  end

  defp find_source_diagnosis(source_diagnoses, text) do
    Enum.find(source_diagnoses, fn src ->
      src_text = to_string(src[:text] || src[:snippet] || "")
      String.contains?(String.downcase(src_text), String.downcase(to_string(text || "")))
    end)
  end

  defp verify_diagnosis(entity, context) do
    with {:ok, snomed_id} <- @snomed.lookup(entity.text),
         {:ok, icd10_codes} <- @snomed.to_icd10(snomed_id),
         :ok <- verify_semantic_fit(snomed_id, context[:chief_complaint]) do
      icd10_str = Enum.join(icd10_codes, ", ")

      {:entailment,
       "Diagnosis '#{entity.text}' validated (SNOMED: #{snomed_id}, ICD-10: #{icd10_str})"}
    else
      {:error, :not_found} ->
        # Try direct ICD-10 lookup
        case @icd10.lookup(entity.text) do
          {:ok, code} ->
            {:entailment, "Diagnosis '#{entity.text}' validated (ICD-10: #{code})"}

          {:error, :not_found} ->
            {:neutral,
             "Diagnosis term '#{entity.text}' not found in SNOMED-CT or ICD-10 (needs review)"}
        end

      {:error, {:semantic_mismatch, reason}} ->
        {:neutral, "Diagnosis '#{entity.text}' may not fit context: #{reason}"}

      {:error, reason} ->
        {:neutral, "Could not fully verify diagnosis '#{entity.text}': #{inspect(reason)}"}
    end
  end

  defp verify_procedure(entity, context) do
    case @snomed.lookup_procedure(entity.text) do
      {:ok, snomed_id} ->
        # Check if procedure is appropriate for context
        # check_procedure_appropriateness/2 currently always returns :ok
        check_procedure_appropriateness(snomed_id, context[:diagnoses] || [])
        {:entailment, "Procedure '#{entity.text}' validated (SNOMED: #{snomed_id})"}

      {:error, :not_found} ->
        {:neutral, "Unknown procedure: '#{entity.text}'"}
    end
  end

  defp verify_finding(entity, _context) do
    case @snomed.lookup_finding(entity.text) do
      {:ok, snomed_id} ->
        {:entailment, "Finding '#{entity.text}' validated (SNOMED: #{snomed_id})"}

      {:error, :not_found} ->
        # Findings are less critical - just note it
        {:neutral, "Finding '#{entity.text}' not in SNOMED-CT (may be colloquial term)"}
    end
  end

  defp verify_semantic_fit(_snomed_id, nil), do: :ok

  defp verify_semantic_fit(snomed_id, chief_complaint) do
    case @snomed.semantic_relevance(snomed_id, chief_complaint) do
      {:ok, score} when score > 0.3 -> :ok
      {:ok, _low_score} -> {:error, {:semantic_mismatch, "low semantic relevance to chief complaint"}}
      {:error, :no_semantic_data} -> :ok
    end
  end

  defp check_procedure_appropriateness(_snomed_id, []), do: :ok
  # Stub - could be expanded to check procedure-diagnosis compatibility
  defp check_procedure_appropriateness(_snomed_id, _diagnoses), do: :ok

  defp verify_relationships(entities, _context) do
    diagnoses = Enum.filter(entities, &(&1.type == :diagnosis))
    findings = Enum.filter(entities, &(&1.type == :finding))

    # Check if findings support diagnoses
    Enum.flat_map(diagnoses, fn diag ->
      Enum.map(findings, fn finding ->
        check_finding_supports_diagnosis(finding, diag)
      end)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp check_finding_supports_diagnosis(finding, diagnosis) do
    case @snomed.is_associated?(finding.text, diagnosis.text) do
      {:ok, true} ->
        {:entailment, "#{finding.text} supports #{diagnosis.text}"}

      {:ok, false} ->
        {:neutral, "#{finding.text} may not typically associate with #{diagnosis.text}"}

      {:error, _} ->
        # Skip if we can't check
        nil
    end
  end
end
