defmodule MedlumLlm.CVL.ICD10Stub do
  @moduledoc """
  Stub implementation of ICD-10 lookup.

  Will be replaced by med_ontology_ex when available.

  ## Supported Codes

  - E11.9 - Type 2 diabetes mellitus without complications
  - E10.9 - Type 1 diabetes mellitus without complications
  - E14.9 - Unspecified diabetes mellitus without complications
  - I10 - Essential (primary) hypertension
  - I21.9 - Acute myocardial infarction, unspecified
  - J18.9 - Pneumonia, unspecified organism
  - I50.9 - Heart failure, unspecified
  - N18.9 - Chronic kidney disease, unspecified
  - J45.909 - Unspecified asthma, uncomplicated
  - J44.9 - Chronic obstructive pulmonary disease, unspecified
  - I48.91 - Unspecified atrial fibrillation
  - I64 - Stroke, not specified as hemorrhage or infarction

  ## Configuration

  In production, configure the real ICD-10 module:

      # config/prod.exs
      config :medlum_llm,
        icd10_module: MedOntologyEx.ICD10
  """

  @codes %{
    "E11.9" => %{
      description: "Type 2 diabetes mellitus without complications",
      chapter: "E00-E89",
      category: "Diabetes mellitus"
    },
    "E10.9" => %{
      description: "Type 1 diabetes mellitus without complications",
      chapter: "E00-E89",
      category: "Diabetes mellitus"
    },
    "E14.9" => %{
      description: "Unspecified diabetes mellitus without complications",
      chapter: "E00-E89",
      category: "Diabetes mellitus"
    },
    "I10" => %{
      description: "Essential (primary) hypertension",
      chapter: "I00-I99",
      category: "Hypertensive diseases"
    },
    "I21.9" => %{
      description: "Acute myocardial infarction, unspecified",
      chapter: "I00-I99",
      category: "Ischemic heart diseases"
    },
    "J18.9" => %{
      description: "Pneumonia, unspecified organism",
      chapter: "J00-J99",
      category: "Pneumonia"
    },
    "I50.9" => %{
      description: "Heart failure, unspecified",
      chapter: "I00-I99",
      category: "Heart failure"
    },
    "N18.9" => %{
      description: "Chronic kidney disease, unspecified",
      chapter: "N00-N99",
      category: "Renal failure"
    },
    "J45.909" => %{
      description: "Unspecified asthma, uncomplicated",
      chapter: "J00-J99",
      category: "Asthma"
    },
    "J44.9" => %{
      description: "Chronic obstructive pulmonary disease, unspecified",
      chapter: "J00-J99",
      category: "COPD"
    },
    "I48.91" => %{
      description: "Unspecified atrial fibrillation",
      chapter: "I00-I99",
      category: "Atrial fibrillation and flutter"
    },
    "I64" => %{
      description: "Stroke, not specified as hemorrhage or infarction",
      chapter: "I00-I99",
      category: "Cerebrovascular diseases"
    },
    "I48.0" => %{
      description: "Paroxysmal atrial fibrillation",
      chapter: "I00-I99",
      category: "Atrial fibrillation and flutter"
    },
    "I48.1" => %{
      description: "Persistent atrial fibrillation",
      chapter: "I00-I99",
      category: "Atrial fibrillation and flutter"
    },
    "I48.2" => %{
      description: "Chronic atrial fibrillation",
      chapter: "I00-I99",
      category: "Atrial fibrillation and flutter"
    },
    "I63.9" => %{
      description: "Cerebral infarction, unspecified",
      chapter: "I00-I99",
      category: "Cerebrovascular diseases"
    },
    "K80.20" => %{
      description: "Calculus of gallbladder without cholecystitis without obstruction",
      chapter: "K00-K95",
      category: "Gallbladder disorders"
    },
    "K35.80" => %{
      description: "Unspecified acute appendicitis",
      chapter: "K00-K95",
      category: "Appendicitis"
    }
  }

  # Map common terms to ICD-10 codes
  @term_to_code %{
    "type 2 diabetes" => "E11.9",
    "type 2 diabetes mellitus" => "E11.9",
    "type 1 diabetes" => "E10.9",
    "type 1 diabetes mellitus" => "E10.9",
    "diabetes" => "E14.9",
    "diabetes mellitus" => "E14.9",
    "hypertension" => "I10",
    "essential hypertension" => "I10",
    "heart attack" => "I21.9",
    "myocardial infarction" => "I21.9",
    "mi" => "I21.9",
    "pneumonia" => "J18.9",
    "heart failure" => "I50.9",
    "congestive heart failure" => "I50.9",
    "chf" => "I50.9",
    "chronic kidney disease" => "N18.9",
    "ckd" => "N18.9",
    "asthma" => "J45.909",
    "copd" => "J44.9",
    "chronic obstructive pulmonary disease" => "J44.9",
    "atrial fibrillation" => "I48.91",
    "afib" => "I48.91",
    "stroke" => "I64",
    "cva" => "I64",
    "cerebrovascular accident" => "I64"
  }

  @doc """
  Look up diagnosis term to get ICD-10 code.

  ## Examples

      iex> ICD10Stub.lookup("type 2 diabetes")
      {:ok, "E11.9"}

      iex> ICD10Stub.lookup("unknown condition")
      {:error, :not_found}
  """
  @spec lookup(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def lookup(term) do
    normalized = String.downcase(term) |> String.trim()

    case Map.fetch(@term_to_code, normalized) do
      {:ok, code} -> {:ok, code}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Validate ICD-10 code exists.

  ## Examples

      iex> ICD10Stub.validate_code("E11.9")
      {:ok, %{description: "Type 2 diabetes mellitus without complications", ...}}

      iex> ICD10Stub.validate_code("ZZZ.99")
      {:error, :invalid_code}
  """
  @spec validate_code(String.t()) :: {:ok, map()} | {:error, :invalid_code}
  def validate_code(code) do
    case Map.fetch(@codes, code) do
      {:ok, info} -> {:ok, info}
      :error -> {:error, :invalid_code}
    end
  end

  @doc """
  Get description for ICD-10 code.

  ## Examples

      iex> ICD10Stub.description("E11.9")
      {:ok, "Type 2 diabetes mellitus without complications"}
  """
  @spec description(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def description(code) do
    case Map.fetch(@codes, code) do
      {:ok, %{description: desc}} -> {:ok, desc}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Get the chapter for an ICD-10 code.

  ## Examples

      iex> ICD10Stub.chapter("E11.9")
      {:ok, "E00-E89"}
  """
  @spec chapter(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def chapter(code) do
    case Map.fetch(@codes, code) do
      {:ok, %{chapter: chapter}} -> {:ok, chapter}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Get the category for an ICD-10 code.

  ## Examples

      iex> ICD10Stub.category("E11.9")
      {:ok, "Diabetes mellitus"}
  """
  @spec category(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def category(code) do
    case Map.fetch(@codes, code) do
      {:ok, %{category: category}} -> {:ok, category}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Check if two codes are in the same category.

  ## Examples

      iex> ICD10Stub.same_category?("I48.91", "I48.0")
      true

      iex> ICD10Stub.same_category?("E11.9", "I10")
      false
  """
  @spec same_category?(String.t(), String.t()) :: boolean()
  def same_category?(code1, code2) do
    with {:ok, cat1} <- category(code1),
         {:ok, cat2} <- category(code2) do
      cat1 == cat2
    else
      _ -> false
    end
  end

  @doc """
  Get all codes in the stub database.

  Useful for testing and debugging.
  """
  @spec all_codes() :: map()
  def all_codes, do: @codes

  @doc """
  Get all term mappings in the stub database.

  Useful for testing and debugging.
  """
  @spec all_terms() :: map()
  def all_terms, do: @term_to_code
end
