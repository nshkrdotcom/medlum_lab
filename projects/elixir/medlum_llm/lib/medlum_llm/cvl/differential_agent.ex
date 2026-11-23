defmodule MedlumLlm.CVL.DifferentialAgent do
  @moduledoc """
  Verifies symptom-diagnosis mapping.

  Part of the 5-agent CVL consensus system with weight 1.0.

  ## Verifies

  - Symptoms support stated diagnosis
  - No contradicting symptoms present
  - Appropriate differential considered
  - Red flags not missed

  ## Source Grounding

  Verification follows source-grounded semantics:

  - **ENTAILMENT**: Diagnosis is supported by symptoms AND both found in source documents
  - **CONTRADICTION**: Symptoms contradict diagnosis OR red flags missed
  - **NEUTRAL**: Cannot verify from available evidence (possible hallucination, needs review)

  ## Examples

      claim = "Patient with chest pain and dyspnea diagnosed with myocardial infarction"
      context = %{
        source_index: %{
          diagnoses: [%{text: "myocardial infarction", doc_id: "note-1"}],
          findings: [%{text: "chest pain", doc_id: "note-1"}, %{text: "dyspnea", doc_id: "note-1"}]
        }
      }

      result = DifferentialAgent.verify(claim, context)
      #=> %{verdict: :entailment, confidence: 1.0, ...}

  """

  @behaviour MedlumLlm.CVL.Agent

  alias MedlumLlm.CVL.Agent

  @differential_db Application.compile_env(
                     :medlum_llm,
                     :differential_db_module,
                     MedlumLlm.CVL.DifferentialDB
                   )

  @impl true
  def name, do: :differential_agent

  @impl true
  def weight, do: 1.0

  @impl true
  def verify(claim, context) do
    symptoms = extract_symptoms(claim)
    diagnoses = extract_diagnoses(claim)

    if Enum.empty?(diagnoses) do
      %{
        verdict: :neutral,
        confidence: 0.5,
        explanations: ["No diagnoses found to verify"],
        evidence: [],
        sub_verdicts: []
      }
    else
      # Source grounding: only reason about diagnoses/symptoms that are supported by source documents.
      source_diagnoses = source_diagnoses(context)
      source_findings = source_findings(context)

      {diagnoses, dx_evidence} =
        Enum.map_reduce(diagnoses, [], fn dx, acc ->
          case find_source_entity(source_diagnoses, dx.name) do
            nil ->
              {nil, acc}

            match ->
              ev = %{
                doc_id: match[:doc_id],
                snippet: match[:text] || match[:snippet] || "",
                entity_type: :diagnosis,
                entity: match
              }

              {dx, [ev | acc]}
          end
        end)

      diagnoses = Enum.reject(diagnoses, &is_nil/1)

      {symptoms, sx_evidence} =
        Enum.map_reduce(symptoms, [], fn sx, acc ->
          case find_source_entity(source_findings, sx.name) do
            nil ->
              {nil, acc}

            match ->
              ev = %{
                doc_id: match[:doc_id],
                snippet: match[:text] || match[:snippet] || "",
                entity_type: :finding,
                entity: match
              }

              {sx, [ev | acc]}
          end
        end)

      symptoms = Enum.reject(symptoms, &is_nil/1)
      evidence = Enum.reverse(dx_evidence ++ sx_evidence)

      if Enum.empty?(diagnoses) do
        %{
          verdict: :neutral,
          confidence: 0.5,
          explanations: ["No diagnoses supported by source documents"],
          evidence: evidence,
          sub_verdicts: []
        }
      else
        verdicts = []

        # Verify symptoms support diagnoses
        verdicts = verdicts ++ verify_symptom_support(symptoms, diagnoses)

        # Check for red flags
        verdicts = verdicts ++ check_red_flags(symptoms, diagnoses, context)

        # Check for contradicting symptoms
        verdicts = verdicts ++ check_contradictions(symptoms, diagnoses)

        if Enum.empty?(verdicts) do
          %{
            verdict: :neutral,
            confidence: 0.5,
            explanations: ["Could not find symptom-diagnosis mapping data"],
            evidence: evidence,
            sub_verdicts: []
          }
        else
          result = Agent.aggregate_verdicts(verdicts)
          %{result | evidence: evidence}
        end
      end
    end
  end

  defp source_diagnoses(context) do
    cond do
      is_map(context[:source_index]) and is_list(get_in(context, [:source_index, :diagnoses])) ->
        get_in(context, [:source_index, :diagnoses])

      true ->
        []
    end
  end

  defp source_findings(context) do
    cond do
      is_map(context[:source_index]) and is_list(get_in(context, [:source_index, :findings])) ->
        get_in(context, [:source_index, :findings])

      true ->
        []
    end
  end

  defp find_source_entity(source_entities, text) do
    Enum.find(source_entities, fn src ->
      src_text = to_string(src[:text] || src[:snippet] || "")
      String.contains?(String.downcase(src_text), String.downcase(to_string(text || "")))
    end)
  end

  @doc """
  Extract symptoms from text.

  Uses ClinicalNerEx when available, otherwise falls back to regex patterns.

  ## Examples

      iex> DifferentialAgent.extract_symptoms("Patient has chest pain and dyspnea")
      [%{name: "chest pain", raw_text: "chest pain"}, %{name: "dyspnea", raw_text: "dyspnea"}]

  """
  @spec extract_symptoms(String.t()) :: [map()]
  def extract_symptoms(claim) do
    if Code.ensure_loaded?(ClinicalNerEx) do
      case apply(ClinicalNerEx, :extract, [claim, [entity_types: [:finding]]]) do
        {:ok, entities} -> Enum.map(entities, &normalize_symptom/1)
        _ -> extract_symptoms_regex(claim)
      end
    else
      extract_symptoms_regex(claim)
    end
  end

  defp extract_symptoms_regex(text) do
    symptom_patterns = [
      {~r/\b(chest pain)\b/i, "chest pain"},
      {~r/\b(shortness of breath|dyspnea|SOB)\b/i, "dyspnea"},
      {~r/\b(fever|febrile)\b/i, "fever"},
      {~r/\b(cough(?:ing)?)\b/i, "cough"},
      {~r/\b(headache)\b/i, "headache"},
      {~r/\b(fatigue|tired(?:ness)?)\b/i, "fatigue"},
      {~r/\b(nausea)\b/i, "nausea"},
      {~r/\b(vomiting)\b/i, "vomiting"},
      {~r/\b(dizziness|dizzy)\b/i, "dizziness"},
      {~r/\b(weakness)\b/i, "weakness"},
      {~r/\b(palpitations)\b/i, "palpitations"},
      {~r/\b(edema|swelling)\b/i, "edema"},
      {~r/\b(diaphoresis|sweating)\b/i, "diaphoresis"},
      {~r/\b(syncope|fainting)\b/i, "syncope"},
      {~r/\b(abdominal pain)\b/i, "abdominal pain"},
      {~r/\b(back pain)\b/i, "back pain"},
      {~r/\b(joint pain|arthralgia)\b/i, "joint pain"},
      {~r/\b(rash)\b/i, "rash"},
      {~r/\b(sore throat|pharyngitis)\b/i, "sore throat"},
      {~r/\b(weight loss)\b/i, "weight loss"},
      {~r/\b(weight gain)\b/i, "weight gain"},
      {~r/\b(blurred vision)\b/i, "blurred vision"},
      {~r/\b(polyuria|increased urination)\b/i, "polyuria"},
      {~r/\b(polydipsia|increased thirst)\b/i, "polydipsia"},
      {~r/\b(neck stiffness)\b/i, "neck stiffness"},
      {~r/\b(photophobia|light sensitivity)\b/i, "photophobia"},
      {~r/\b(confusion|altered mental status)\b/i, "confusion"},
      {~r/\b(leg pain)\b/i, "leg pain"},
      {~r/\b(chest tightness)\b/i, "chest tightness"}
    ]

    Enum.flat_map(symptom_patterns, fn {regex, normalized_name} ->
      if Regex.match?(regex, text) do
        [%{name: normalized_name, raw_text: normalized_name}]
      else
        []
      end
    end)
    |> Enum.uniq_by(& &1.name)
  end

  defp normalize_symptom(entity) do
    %{
      name: String.downcase(entity[:text] || entity["text"] || ""),
      raw_text: entity[:text] || entity["text"]
    }
  end

  @doc """
  Extract diagnoses from text.

  Uses pattern matching to identify diagnoses mentioned in claims.

  ## Examples

      iex> DifferentialAgent.extract_diagnoses("Diagnosed with myocardial infarction")
      [%{name: "myocardial infarction", raw_text: "myocardial infarction"}]

  """
  @spec extract_diagnoses(String.t()) :: [map()]
  def extract_diagnoses(claim) do
    diagnosis_patterns = [
      {~r/diagnosed with\s+([a-z][a-z\s]+?)(?:\.|,|$)/i, nil},
      {~r/diagnosis of\s+([a-z][a-z\s]+?)(?:\.|,|$)/i, nil},
      {~r/\b(myocardial infarction|heart attack|MI)\b/i, "myocardial infarction"},
      {~r/\b(pneumonia)\b/i, "pneumonia"},
      {~r/\b(type [12] diabetes(?:\s+mellitus)?)\b/i, "diabetes"},
      {~r/\b(hypertension)\b/i, "hypertension"},
      {~r/\b(heart failure|CHF)\b/i, "heart failure"},
      {~r/\b(stroke|CVA)\b/i, "stroke"},
      {~r/\b(pulmonary embolism|PE)\b/i, "pulmonary embolism"},
      {~r/\b(deep vein thrombosis|DVT)\b/i, "deep vein thrombosis"},
      {~r/\b(COPD)\b/i, "copd"},
      {~r/\b(asthma)\b/i, "asthma"},
      {~r/\b(appendicitis)\b/i, "appendicitis"},
      {~r/\b(sepsis)\b/i, "sepsis"},
      {~r/\b(meningitis)\b/i, "meningitis"}
    ]

    Enum.flat_map(diagnosis_patterns, fn {regex, normalized_name} ->
      case Regex.run(regex, claim) do
        [_, captured] ->
          name = normalized_name || String.downcase(String.trim(captured))
          [%{name: name, raw_text: captured}]

        nil ->
          []
      end
    end)
    |> Enum.uniq_by(& &1.name)
  end

  defp verify_symptom_support(symptoms, diagnoses) do
    symptom_names = Enum.map(symptoms, & &1.name)

    Enum.flat_map(diagnoses, fn diagnosis ->
      case @differential_db.get_supporting_symptoms(diagnosis.name) do
        {:ok, %{required: required, supporting: supporting}} ->
          required_present = Enum.filter(required, &(&1 in symptom_names))
          supporting_present = Enum.filter(supporting, &(&1 in symptom_names))

          cond do
            # All required symptoms present
            length(required) > 0 and length(required_present) == length(required) ->
              [
                {:entailment,
                 "All required symptoms present for #{diagnosis.name}: #{Enum.join(required_present, ", ")}"}
              ]

            # Some required missing
            length(required) > 0 and length(required_present) < length(required) ->
              missing = required -- required_present

              [
                {:neutral,
                 "Missing required symptoms for #{diagnosis.name}: #{Enum.join(missing, ", ")}"}
              ]

            # No requirements, check supporting
            length(supporting_present) > 0 ->
              [
                {:entailment,
                 "Supporting symptoms present for #{diagnosis.name}: #{Enum.join(supporting_present, ", ")}"}
              ]

            # No symptoms at all
            Enum.empty?(symptoms) ->
              [{:neutral, "No symptoms documented to support #{diagnosis.name}"}]

            true ->
              [{:neutral, "No matching symptoms found for #{diagnosis.name}"}]
          end

        {:error, :not_found} ->
          [{:neutral, "No symptom mapping data for #{diagnosis.name}"}]
      end
    end)
  end

  defp check_red_flags(symptoms, diagnoses, _context) do
    symptom_names = Enum.map(symptoms, & &1.name)
    diagnosis_names = Enum.map(diagnoses, & &1.name)

    case @differential_db.get_red_flags(symptom_names) do
      {:ok, red_flags} ->
        unaddressed =
          Enum.reject(red_flags, fn flag ->
            # Check if the red flag condition is addressed by a diagnosis
            Enum.any?(diagnosis_names, fn dx ->
              String.contains?(dx, flag.condition) or
                Enum.any?(flag.requires_workup_for, &String.contains?(dx, &1))
            end)
          end)

        Enum.map(unaddressed, fn flag ->
          {:contradiction, "Red flag not addressed: #{flag.description}"}
        end)

      {:error, :no_red_flags} ->
        []
    end
  end

  defp check_contradictions(symptoms, diagnoses) do
    symptom_names = Enum.map(symptoms, & &1.name)

    Enum.flat_map(diagnoses, fn diagnosis ->
      case @differential_db.get_contradicting_symptoms(diagnosis.name) do
        {:ok, contradicting} ->
          found_contradictions = Enum.filter(contradicting, &(&1 in symptom_names))

          Enum.map(found_contradictions, fn contra ->
            {:contradiction,
             "Symptom '#{contra}' typically contradicts diagnosis of #{diagnosis.name}"}
          end)

        {:error, :not_found} ->
          []
      end
    end)
  end
end
