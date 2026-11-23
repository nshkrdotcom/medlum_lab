defmodule MedlumLlm.CVL.DifferentialDB do
  @moduledoc """
  Stub database for symptom-diagnosis mappings.

  Provides symptom-diagnosis relationships for the DifferentialAgent to verify
  that stated symptoms support given diagnoses and to detect red flags.

  Will be replaced by med_ontology_ex when available.

  ## Configuration

  In production, configure the real DifferentialDB module:

      # config/prod.exs
      config :medlum_llm,
        differential_db_module: MedOntologyEx.DifferentialDB

  ## Data Structure

  Each diagnosis has:
  - `required`: Symptoms that must be present (if non-empty)
  - `supporting`: Symptoms that support but aren't required
  - `contradicting`: Symptoms that would argue against the diagnosis

  """

  @diagnosis_symptoms %{
    "myocardial infarction" => %{
      required: [],
      supporting: [
        "chest pain",
        "dyspnea",
        "diaphoresis",
        "nausea",
        "weakness",
        "palpitations"
      ],
      contradicting: []
    },
    "pneumonia" => %{
      required: [],
      supporting: ["cough", "fever", "dyspnea", "chest pain"],
      contradicting: []
    },
    "diabetes" => %{
      required: [],
      supporting: ["polyuria", "polydipsia", "fatigue", "blurred vision", "weight loss"],
      contradicting: []
    },
    "hypertension" => %{
      required: [],
      supporting: ["headache", "dizziness", "blurred vision"],
      contradicting: []
    },
    "heart failure" => %{
      required: [],
      supporting: ["dyspnea", "edema", "fatigue", "palpitations"],
      contradicting: []
    },
    "stroke" => %{
      required: [],
      supporting: ["weakness", "dizziness", "headache", "blurred vision", "syncope"],
      contradicting: []
    },
    "pulmonary embolism" => %{
      required: [],
      supporting: ["dyspnea", "chest pain", "cough", "palpitations", "syncope"],
      contradicting: []
    },
    "deep vein thrombosis" => %{
      required: [],
      supporting: ["edema", "leg pain"],
      contradicting: []
    },
    "copd" => %{
      required: [],
      supporting: ["dyspnea", "cough", "fatigue"],
      contradicting: []
    },
    "asthma" => %{
      required: [],
      supporting: ["dyspnea", "cough", "chest tightness"],
      contradicting: []
    },
    "appendicitis" => %{
      required: [],
      supporting: ["abdominal pain", "nausea", "vomiting", "fever"],
      contradicting: []
    },
    "sepsis" => %{
      required: [],
      supporting: ["fever", "weakness", "dizziness", "confusion"],
      contradicting: []
    },
    "meningitis" => %{
      required: [],
      supporting: ["headache", "fever", "neck stiffness", "photophobia"],
      contradicting: []
    }
  }

  @red_flags %{
    "chest pain" => [
      %{
        description: "Chest pain with dyspnea could indicate MI or PE",
        condition: "cardiac emergency",
        requires_workup_for: ["myocardial infarction", "pulmonary embolism"]
      }
    ],
    "syncope" => [
      %{
        description: "Syncope requires cardiac and neurological workup",
        condition: "syncope workup",
        requires_workup_for: ["arrhythmia", "stroke"]
      }
    ],
    "fever" => [
      %{
        description: "High fever with headache could indicate meningitis",
        condition: "infection workup",
        requires_workup_for: ["meningitis", "sepsis"]
      }
    ],
    "weakness" => [
      %{
        description: "Sudden weakness could indicate stroke",
        condition: "stroke workup",
        requires_workup_for: ["stroke"]
      }
    ]
  }

  @doc """
  Get supporting and required symptoms for a diagnosis.

  ## Examples

      iex> DifferentialDB.get_supporting_symptoms("myocardial infarction")
      {:ok, %{required: [], supporting: ["chest pain", "dyspnea", ...], contradicting: []}}

      iex> DifferentialDB.get_supporting_symptoms("unknown disease")
      {:error, :not_found}

  """
  @spec get_supporting_symptoms(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_supporting_symptoms(diagnosis) do
    normalized = normalize_diagnosis(diagnosis)

    case Map.fetch(@diagnosis_symptoms, normalized) do
      {:ok, info} -> {:ok, info}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Get red flags for a set of symptoms.

  Red flags are symptom combinations that suggest a potentially serious
  condition requiring workup.

  ## Examples

      iex> DifferentialDB.get_red_flags(["chest pain", "dyspnea"])
      {:ok, [%{description: "Chest pain with dyspnea could indicate MI or PE", ...}]}

      iex> DifferentialDB.get_red_flags(["mild headache"])
      {:error, :no_red_flags}

  """
  @spec get_red_flags([String.t()]) :: {:ok, [map()]} | {:error, :no_red_flags}
  def get_red_flags(symptoms) do
    flags =
      Enum.flat_map(symptoms, fn symptom ->
        Map.get(@red_flags, symptom, [])
      end)
      |> Enum.uniq()

    if Enum.empty?(flags) do
      {:error, :no_red_flags}
    else
      {:ok, flags}
    end
  end

  @doc """
  Get symptoms that contradict a diagnosis.

  Returns a list of symptoms that, if present, would argue against
  the stated diagnosis.

  ## Examples

      iex> DifferentialDB.get_contradicting_symptoms("pneumonia")
      {:ok, []}

      iex> DifferentialDB.get_contradicting_symptoms("unknown")
      {:error, :not_found}

  """
  @spec get_contradicting_symptoms(String.t()) :: {:ok, [String.t()]} | {:error, :not_found}
  def get_contradicting_symptoms(diagnosis) do
    normalized = normalize_diagnosis(diagnosis)

    case Map.fetch(@diagnosis_symptoms, normalized) do
      {:ok, %{contradicting: contras}} -> {:ok, contras}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  List all supported diagnoses in the database.

  ## Examples

      iex> DifferentialDB.list_diagnoses()
      ["appendicitis", "asthma", "copd", ...]

  """
  @spec list_diagnoses() :: [String.t()]
  def list_diagnoses do
    Map.keys(@diagnosis_symptoms) |> Enum.sort()
  end

  @doc """
  List all red flag symptoms.

  ## Examples

      iex> DifferentialDB.list_red_flag_symptoms()
      ["chest pain", "fever", "syncope", "weakness"]

  """
  @spec list_red_flag_symptoms() :: [String.t()]
  def list_red_flag_symptoms do
    Map.keys(@red_flags) |> Enum.sort()
  end

  defp normalize_diagnosis(diagnosis) do
    diagnosis
    |> String.downcase()
    |> String.trim()
    |> String.replace("type 1 ", "")
    |> String.replace("type 2 ", "")
    |> String.replace(" mellitus", "")
  end
end
