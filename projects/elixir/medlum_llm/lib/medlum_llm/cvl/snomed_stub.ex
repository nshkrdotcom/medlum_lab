defmodule MedlumLlm.CVL.SNOMEDStub do
  @moduledoc """
  Stub implementation of SNOMED-CT lookup.

  Will be replaced by med_ontology_ex when available.

  ## Supported Diagnoses

  - Type 2 diabetes mellitus, Type 1 diabetes
  - Hypertension, Essential hypertension
  - Myocardial infarction (MI, heart attack)
  - Pneumonia
  - Congestive heart failure (CHF)
  - Chronic kidney disease (CKD)
  - Asthma, COPD
  - Atrial fibrillation (afib)
  - Stroke (CVA)

  ## Configuration

  In production, configure the real SNOMED module:

      # config/prod.exs
      config :medlum_llm,
        snomed_module: MedOntologyEx.SNOMED
  """

  @diagnoses %{
    "type 2 diabetes mellitus" => %{
      snomed_id: "44054006",
      icd10: ["E11.9"],
      related_findings: ["increased thirst", "polyuria", "fatigue"],
      semantic_category: "metabolic"
    },
    "type 2 diabetes" => %{snomed_id: "44054006", icd10: ["E11.9"]},
    "type 1 diabetes mellitus" => %{
      snomed_id: "46635009",
      icd10: ["E10.9"],
      related_findings: ["increased thirst", "polyuria", "weight loss"],
      semantic_category: "metabolic"
    },
    "type 1 diabetes" => %{snomed_id: "46635009", icd10: ["E10.9"]},
    "diabetes mellitus" => %{snomed_id: "73211009", icd10: ["E14.9"]},
    "hypertension" => %{
      snomed_id: "38341003",
      icd10: ["I10"],
      related_findings: ["headache", "elevated blood pressure"],
      semantic_category: "cardiovascular"
    },
    "essential hypertension" => %{snomed_id: "59621000", icd10: ["I10"]},
    "myocardial infarction" => %{
      snomed_id: "22298006",
      icd10: ["I21.9"],
      related_findings: ["chest pain", "dyspnea", "diaphoresis"],
      semantic_category: "cardiovascular"
    },
    "heart attack" => %{snomed_id: "22298006", icd10: ["I21.9"]},
    "mi" => %{snomed_id: "22298006", icd10: ["I21.9"]},
    "pneumonia" => %{
      snomed_id: "233604007",
      icd10: ["J18.9"],
      related_findings: ["cough", "fever", "dyspnea"],
      semantic_category: "respiratory"
    },
    "congestive heart failure" => %{
      snomed_id: "42343007",
      icd10: ["I50.9"],
      related_findings: ["edema", "dyspnea", "fatigue"],
      semantic_category: "cardiovascular"
    },
    "chf" => %{snomed_id: "42343007", icd10: ["I50.9"]},
    "heart failure" => %{snomed_id: "84114007", icd10: ["I50.9"]},
    "chronic kidney disease" => %{
      snomed_id: "709044004",
      icd10: ["N18.9"],
      related_findings: ["fatigue", "edema"],
      semantic_category: "renal"
    },
    "ckd" => %{snomed_id: "709044004", icd10: ["N18.9"]},
    "asthma" => %{
      snomed_id: "195967001",
      icd10: ["J45.909"],
      related_findings: ["wheezing", "dyspnea", "cough"],
      semantic_category: "respiratory"
    },
    "copd" => %{
      snomed_id: "13645005",
      icd10: ["J44.9"],
      related_findings: ["dyspnea", "cough"],
      semantic_category: "respiratory"
    },
    "chronic obstructive pulmonary disease" => %{snomed_id: "13645005", icd10: ["J44.9"]},
    "atrial fibrillation" => %{
      snomed_id: "49436004",
      icd10: ["I48.91"],
      related_findings: ["palpitations", "dyspnea"],
      semantic_category: "cardiovascular"
    },
    "afib" => %{snomed_id: "49436004", icd10: ["I48.91"]},
    "stroke" => %{
      snomed_id: "230690007",
      icd10: ["I64"],
      related_findings: ["weakness", "speech difficulty", "facial droop"],
      semantic_category: "neurological"
    },
    "cva" => %{snomed_id: "230690007", icd10: ["I64"]},
    "cerebrovascular accident" => %{snomed_id: "230690007", icd10: ["I64"]}
  }

  @findings %{
    "chest pain" => %{snomed_id: "29857009"},
    "shortness of breath" => %{snomed_id: "267036007"},
    "dyspnea" => %{snomed_id: "267036007"},
    "fever" => %{snomed_id: "386661006"},
    "cough" => %{snomed_id: "49727002"},
    "headache" => %{snomed_id: "25064002"},
    "fatigue" => %{snomed_id: "84229001"},
    "nausea" => %{snomed_id: "422587007"},
    "vomiting" => %{snomed_id: "422400008"},
    "edema" => %{snomed_id: "79654002"},
    "swelling" => %{snomed_id: "65124004"},
    "increased thirst" => %{snomed_id: "17173007"},
    "polyuria" => %{snomed_id: "28442001"},
    "palpitations" => %{snomed_id: "80313002"},
    "wheezing" => %{snomed_id: "56018004"},
    "weakness" => %{snomed_id: "13791008"},
    "speech difficulty" => %{snomed_id: "29164008"},
    "facial droop" => %{snomed_id: "95667003"},
    "weight loss" => %{snomed_id: "89362005"},
    "diaphoresis" => %{snomed_id: "52613005"},
    "elevated blood pressure" => %{snomed_id: "38341003"}
  }

  @procedures %{
    "coronary artery bypass" => %{snomed_id: "232717009"},
    "coronary artery bypass graft" => %{snomed_id: "232717009"},
    "cabg" => %{snomed_id: "232717009"},
    "angioplasty" => %{snomed_id: "41339005"},
    "percutaneous coronary intervention" => %{snomed_id: "415070008"},
    "pci" => %{snomed_id: "415070008"},
    "appendectomy" => %{snomed_id: "80146002"},
    "cholecystectomy" => %{snomed_id: "38102005"},
    "cardiac catheterization" => %{snomed_id: "41976001"},
    "dialysis" => %{snomed_id: "108241001"},
    "hemodialysis" => %{snomed_id: "302497006"}
  }

  @doc """
  Look up diagnosis in SNOMED-CT.

  ## Examples

      iex> SNOMEDStub.lookup("type 2 diabetes mellitus")
      {:ok, "44054006"}

      iex> SNOMEDStub.lookup("unknown condition")
      {:error, :not_found}
  """
  @spec lookup(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def lookup(term) do
    normalized = String.downcase(term) |> String.trim()

    case Map.fetch(@diagnoses, normalized) do
      {:ok, info} -> {:ok, info.snomed_id}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Look up finding in SNOMED-CT.

  ## Examples

      iex> SNOMEDStub.lookup_finding("chest pain")
      {:ok, "29857009"}
  """
  @spec lookup_finding(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def lookup_finding(term) do
    normalized = String.downcase(term) |> String.trim()

    case Map.fetch(@findings, normalized) do
      {:ok, info} -> {:ok, info.snomed_id}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Look up procedure in SNOMED-CT.

  ## Examples

      iex> SNOMEDStub.lookup_procedure("cabg")
      {:ok, "232717009"}
  """
  @spec lookup_procedure(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def lookup_procedure(term) do
    normalized = String.downcase(term) |> String.trim()

    case Map.fetch(@procedures, normalized) do
      {:ok, info} -> {:ok, info.snomed_id}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Map SNOMED-CT concept to ICD-10 codes.

  ## Examples

      iex> SNOMEDStub.to_icd10("44054006")
      {:ok, ["E11.9"]}
  """
  @spec to_icd10(String.t()) :: {:ok, [String.t()]} | {:error, :no_mapping}
  def to_icd10(snomed_id) do
    diag = Enum.find(@diagnoses, fn {_, v} -> v.snomed_id == snomed_id end)

    case diag do
      {_, %{icd10: codes}} -> {:ok, codes}
      nil -> {:error, :no_mapping}
    end
  end

  @doc """
  Check if finding is associated with diagnosis.

  ## Examples

      iex> SNOMEDStub.is_associated?("chest pain", "myocardial infarction")
      {:ok, true}

      iex> SNOMEDStub.is_associated?("cough", "hypertension")
      {:ok, false}
  """
  @spec is_associated?(String.t(), String.t()) :: {:ok, boolean()} | {:error, :no_data}
  def is_associated?(finding_term, diagnosis_term) do
    finding_normalized = String.downcase(finding_term)
    diagnosis_normalized = String.downcase(diagnosis_term)

    case Map.fetch(@diagnoses, diagnosis_normalized) do
      {:ok, %{related_findings: findings}} ->
        is_related =
          Enum.any?(findings, fn f ->
            String.contains?(finding_normalized, f) or String.contains?(f, finding_normalized)
          end)

        {:ok, is_related}

      _ ->
        {:error, :no_data}
    end
  end

  @doc """
  Calculate semantic relevance between concept and text.

  Returns a score from 0.0 to 1.0 based on how many related findings
  appear in the text.

  ## Examples

      iex> SNOMEDStub.semantic_relevance("44054006", "patient has increased thirst and polyuria")
      {:ok, 0.67}
  """
  @spec semantic_relevance(String.t(), String.t()) :: {:ok, float()} | {:error, :no_semantic_data}
  def semantic_relevance(snomed_id, text) do
    # Find the entry with related_findings for this SNOMED ID
    diag =
      Enum.find(@diagnoses, fn {_, v} ->
        v.snomed_id == snomed_id and Map.has_key?(v, :related_findings)
      end)

    case diag do
      {_, %{related_findings: findings}} ->
        text_lower = String.downcase(text)
        matches = Enum.count(findings, fn f -> String.contains?(text_lower, f) end)
        score = matches / max(length(findings), 1)
        {:ok, score}

      _ ->
        {:error, :no_semantic_data}
    end
  end

  @doc """
  Get the semantic category for a diagnosis.

  Categories: metabolic, cardiovascular, respiratory, renal, neurological

  ## Examples

      iex> SNOMEDStub.semantic_category("44054006")
      {:ok, "metabolic"}
  """
  @spec semantic_category(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def semantic_category(snomed_id) do
    # Find the entry with semantic_category for this SNOMED ID
    diag =
      Enum.find(@diagnoses, fn {_, v} ->
        v.snomed_id == snomed_id and Map.has_key?(v, :semantic_category)
      end)

    case diag do
      {_, %{semantic_category: category}} -> {:ok, category}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Get all diagnoses in the stub database.

  Useful for testing and debugging.
  """
  @spec all_diagnoses() :: map()
  def all_diagnoses, do: @diagnoses

  @doc """
  Get all findings in the stub database.

  Useful for testing and debugging.
  """
  @spec all_findings() :: map()
  def all_findings, do: @findings

  @doc """
  Get all procedures in the stub database.

  Useful for testing and debugging.
  """
  @spec all_procedures() :: map()
  def all_procedures, do: @procedures
end
