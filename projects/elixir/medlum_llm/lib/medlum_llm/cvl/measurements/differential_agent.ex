defmodule MedlumLlm.CVL.Measurements.DifferentialAgent do
  @moduledoc """
  Forge Measurement for symptom-diagnosis mapping verification.

  This measurement validates clinical reasoning by:
  - Checking if symptoms support the stated diagnosis
  - Verifying differential diagnosis completeness
  - Detecting symptom-diagnosis mismatches
  - Validating clinical presentation consistency

  ## Verdict Types

  - `:entailment` - Symptoms support the diagnosis
  - `:contradiction` - Symptoms inconsistent with diagnosis
  - `:neutral` - Unable to verify (insufficient clinical data)

  ## Example

      iex> samples = [%Forge.Sample{data: %{claims: [
      ...>   %{text: "chest pain, shortness of breath"},
      ...>   %{text: "diagnosed with myocardial infarction"}
      ...> ]}}]
      iex> {:ok, results} = DifferentialAgent.compute(samples)
      iex> results["sample_id"].verdict
      :entailment
  """

  @behaviour Forge.Measurement

  @measurement_version 1

  @type verdict :: :entailment | :contradiction | :neutral

  @type result :: %{
          verdict: verdict(),
          confidence: float(),
          reasoning: String.t(),
          evidence: [map()],
          symptom_diagnosis_map: map()
        }

  @impl true
  @spec compute([Forge.Sample.t()]) :: {:ok, map()} | {:error, term()}
  def compute(samples) do
    results =
      samples
      |> Enum.map(fn sample ->
        verdict = verify_symptom_diagnosis(sample)
        {sample.id, verdict}
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

    "differential_agent_#{config_hash}"
  end

  @impl true
  @spec version() :: pos_integer()
  def version, do: @measurement_version

  @impl true
  @spec dependencies() :: [module()]
  def dependencies, do: []

  @impl true
  @spec async?() :: boolean()
  def async?, do: true

  @impl true
  @spec timeout() :: pos_integer()
  def timeout, do: 60_000

  @doc """
  Get current configuration for this measurement.
  """
  @spec config() :: map()
  def config do
    %{
      confidence_threshold: 0.8,
      min_symptom_match: 0.3,
      require_key_symptoms: true
    }
  end

  # Symptom-diagnosis mapping knowledge base
  @diagnosis_symptoms %{
    "myocardial infarction" => %{
      key_symptoms: ["chest pain", "shortness of breath"],
      supporting_symptoms: [
        "radiating pain",
        "arm pain",
        "jaw pain",
        "sweating",
        "nausea",
        "fatigue"
      ],
      contradicting_symptoms: [],
      risk_factors: ["hypertension", "diabetes", "smoking", "obesity", "family history"]
    },
    "heart failure" => %{
      key_symptoms: ["shortness of breath", "edema", "fatigue"],
      supporting_symptoms: [
        "orthopnea",
        "paroxysmal nocturnal dyspnea",
        "weight gain",
        "jugular venous distension"
      ],
      contradicting_symptoms: [],
      risk_factors: ["hypertension", "coronary artery disease", "diabetes", "obesity"]
    },
    "pneumonia" => %{
      key_symptoms: ["cough", "fever", "shortness of breath"],
      supporting_symptoms: ["productive cough", "chest pain", "chills", "fatigue", "sputum"],
      contradicting_symptoms: [],
      risk_factors: ["immunocompromised", "elderly", "smoking", "copd"]
    },
    "copd" => %{
      key_symptoms: ["chronic cough", "shortness of breath", "wheezing"],
      supporting_symptoms: ["sputum production", "chest tightness", "fatigue"],
      contradicting_symptoms: [],
      risk_factors: ["smoking", "occupational exposure", "alpha-1 antitrypsin deficiency"]
    },
    "diabetes" => %{
      key_symptoms: ["polyuria", "polydipsia", "weight loss"],
      supporting_symptoms: ["fatigue", "blurred vision", "slow healing", "frequent infections"],
      contradicting_symptoms: [],
      risk_factors: ["obesity", "family history", "sedentary lifestyle"]
    },
    "type 2 diabetes" => %{
      key_symptoms: ["polyuria", "polydipsia"],
      supporting_symptoms: [
        "fatigue",
        "blurred vision",
        "slow healing",
        "numbness",
        "tingling"
      ],
      contradicting_symptoms: [],
      risk_factors: ["obesity", "family history", "metabolic syndrome"]
    },
    "hypertension" => %{
      key_symptoms: [],
      supporting_symptoms: ["headache", "dizziness", "blurred vision", "nosebleeds"],
      contradicting_symptoms: [],
      risk_factors: ["obesity", "high sodium diet", "sedentary lifestyle", "stress"]
    },
    "stroke" => %{
      key_symptoms: ["sudden weakness", "facial droop", "speech difficulty"],
      supporting_symptoms: [
        "confusion",
        "vision problems",
        "severe headache",
        "dizziness",
        "loss of balance"
      ],
      contradicting_symptoms: [],
      risk_factors: ["hypertension", "atrial fibrillation", "diabetes", "smoking"]
    },
    "appendicitis" => %{
      key_symptoms: ["abdominal pain", "right lower quadrant pain"],
      supporting_symptoms: ["nausea", "vomiting", "fever", "loss of appetite", "rebound tenderness"],
      contradicting_symptoms: ["chronic pain", "diarrhea"],
      risk_factors: []
    },
    "urinary tract infection" => %{
      key_symptoms: ["dysuria", "urinary frequency"],
      supporting_symptoms: ["urgency", "suprapubic pain", "hematuria", "cloudy urine", "fever"],
      contradicting_symptoms: [],
      risk_factors: ["female", "sexual activity", "catheterization"]
    }
  }

  # Private functions

  @spec verify_symptom_diagnosis(Forge.Sample.t()) :: result()
  defp verify_symptom_diagnosis(sample) do
    claims = sample.data[:claims] || []
    text = extract_full_text(sample)

    # Extract symptoms and diagnoses
    symptoms = extract_symptoms(text, claims)
    diagnoses = extract_diagnoses(text, claims)

    if Enum.empty?(diagnoses) do
      %{
        verdict: :neutral,
        confidence: 1.0,
        reasoning: "No diagnoses found to verify",
        evidence: [],
        symptom_diagnosis_map: %{symptoms: symptoms, diagnoses: []}
      }
    else
      # Verify each diagnosis against symptoms
      verifications = Enum.map(diagnoses, &verify_diagnosis_support(&1, symptoms))

      aggregate_verifications(verifications, symptoms, diagnoses)
    end
  end

  @spec extract_full_text(Forge.Sample.t()) :: String.t()
  defp extract_full_text(sample) do
    data = sample.data

    [
      data[:source_document],
      data[:generated_summary],
      data[:question]
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  @spec extract_symptoms(String.t(), [map()]) :: [String.t()]
  defp extract_symptoms(text, _claims) do
    lower_text = String.downcase(text)

    all_symptoms =
      @diagnosis_symptoms
      |> Enum.flat_map(fn {_diagnosis, data} ->
        (data[:key_symptoms] || []) ++ (data[:supporting_symptoms] || [])
      end)
      |> Enum.uniq()

    # Find symptoms present in text
    Enum.filter(all_symptoms, fn symptom ->
      # Check for exact match or fuzzy match
      String.contains?(lower_text, symptom) or
        synonym_match?(lower_text, symptom)
    end)
  end

  @spec synonym_match?(String.t(), String.t()) :: boolean()
  defp synonym_match?(text, symptom) do
    synonyms = %{
      "chest pain" => ["chest discomfort", "angina", "chest tightness"],
      "shortness of breath" => ["dyspnea", "difficulty breathing", "breathlessness", "sob"],
      "edema" => ["swelling", "fluid retention"],
      "cough" => ["coughing"],
      "fever" => ["febrile", "elevated temperature", "pyrexia"],
      "fatigue" => ["tiredness", "weakness", "exhaustion"],
      "headache" => ["head pain", "cephalgia"],
      "nausea" => ["nauseated", "queasy"],
      "vomiting" => ["emesis"],
      "polyuria" => ["frequent urination", "increased urination"],
      "polydipsia" => ["increased thirst", "excessive thirst"],
      "dysuria" => ["painful urination", "burning urination"]
    }

    case Map.get(synonyms, symptom) do
      nil -> false
      syns -> Enum.any?(syns, &String.contains?(text, &1))
    end
  end

  @spec extract_diagnoses(String.t(), [map()]) :: [String.t()]
  defp extract_diagnoses(text, claims) do
    lower_text = String.downcase(text)

    # Find diagnoses from knowledge base present in text
    known_diagnoses =
      @diagnosis_symptoms
      |> Map.keys()
      |> Enum.filter(&String.contains?(lower_text, &1))

    # Also check claims tagged as diagnoses
    claim_diagnoses =
      claims
      |> Enum.filter(&(&1[:type] == :diagnosis))
      |> Enum.map(&String.downcase(&1[:text] || ""))
      |> Enum.flat_map(fn claim_text ->
        Enum.filter(Map.keys(@diagnosis_symptoms), &String.contains?(claim_text, &1))
      end)

    Enum.uniq(known_diagnoses ++ claim_diagnoses)
  end

  @spec verify_diagnosis_support(String.t(), [String.t()]) :: map()
  defp verify_diagnosis_support(diagnosis, symptoms) do
    case Map.get(@diagnosis_symptoms, diagnosis) do
      nil ->
        %{
          diagnosis: diagnosis,
          verdict: :neutral,
          confidence: 0.5,
          reasoning: "Diagnosis not in knowledge base",
          key_symptoms_found: [],
          supporting_symptoms_found: [],
          contradicting_symptoms_found: [],
          match_score: 0.0
        }

      diagnosis_data ->
        verify_against_knowledge(diagnosis, diagnosis_data, symptoms)
    end
  end

  @spec verify_against_knowledge(String.t(), map(), [String.t()]) :: map()
  defp verify_against_knowledge(diagnosis, diagnosis_data, symptoms) do
    key_symptoms = diagnosis_data[:key_symptoms] || []
    supporting_symptoms = diagnosis_data[:supporting_symptoms] || []
    contradicting_symptoms = diagnosis_data[:contradicting_symptoms] || []

    # Find matches
    key_found = Enum.filter(key_symptoms, &(&1 in symptoms))
    supporting_found = Enum.filter(supporting_symptoms, &(&1 in symptoms))
    contradicting_found = Enum.filter(contradicting_symptoms, &(&1 in symptoms))

    # Calculate match score
    key_match_ratio =
      if length(key_symptoms) > 0 do
        length(key_found) / length(key_symptoms)
      else
        1.0
      end

    supporting_match_ratio =
      if length(supporting_symptoms) > 0 do
        length(supporting_found) / length(supporting_symptoms)
      else
        0.0
      end

    # Weighted score: key symptoms are more important
    match_score = key_match_ratio * 0.7 + supporting_match_ratio * 0.3

    # Determine verdict
    {verdict, confidence, reasoning} =
      cond do
        length(contradicting_found) > 0 ->
          {:contradiction, 0.85, "Contradicting symptoms found: #{Enum.join(contradicting_found, ", ")}"}

        key_match_ratio >= 0.5 and match_score >= 0.3 ->
          {:entailment, 0.8 + match_score * 0.15, "Key symptoms support diagnosis"}

        key_match_ratio > 0 ->
          {:neutral, 0.6, "Partial symptom support for diagnosis"}

        length(key_symptoms) == 0 and length(supporting_found) > 0 ->
          {:entailment, 0.7, "Supporting symptoms present (no key symptoms defined)"}

        true ->
          {:neutral, 0.5, "Insufficient symptom evidence"}
      end

    %{
      diagnosis: diagnosis,
      verdict: verdict,
      confidence: confidence,
      reasoning: reasoning,
      key_symptoms_found: key_found,
      supporting_symptoms_found: supporting_found,
      contradicting_symptoms_found: contradicting_found,
      match_score: match_score
    }
  end

  @spec aggregate_verifications([map()], [String.t()], [String.t()]) :: result()
  defp aggregate_verifications(verifications, symptoms, diagnoses) do
    verdicts = Enum.map(verifications, & &1.verdict)
    confidences = Enum.map(verifications, & &1.confidence)

    {final_verdict, reasoning} =
      cond do
        Enum.any?(verdicts, &(&1 == :contradiction)) ->
          {:contradiction, "Symptom-diagnosis mismatch detected"}

        Enum.all?(verdicts, &(&1 == :entailment)) ->
          {:entailment, "Symptoms support all diagnoses"}

        Enum.any?(verdicts, &(&1 == :entailment)) ->
          {:neutral, "Partial support - some diagnoses verified"}

        true ->
          {:neutral, "Insufficient evidence to verify symptom-diagnosis relationship"}
      end

    avg_confidence =
      if length(confidences) > 0 do
        Enum.sum(confidences) / length(confidences)
      else
        0.5
      end

    %{
      verdict: final_verdict,
      confidence: avg_confidence,
      reasoning: reasoning,
      evidence: verifications,
      symptom_diagnosis_map: %{
        symptoms: symptoms,
        diagnoses: diagnoses,
        verifications: verifications
      }
    }
  end
end
