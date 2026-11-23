defmodule MedlumLlm.CVL.LOINCStub do
  @moduledoc """
  Stub implementation of LOINC lookup.

  Will be replaced by med_ontology_ex when available.
  Provides basic validation using a small in-memory dictionary.

  ## Supported Lab Tests

  This stub supports a limited set of common lab tests for testing:

  - hemoglobin_a1c - Diabetes monitoring
  - glucose - Blood sugar levels
  - hemoglobin - Oxygen-carrying capacity
  - wbc - White blood cell count
  - creatinine - Kidney function
  - bun - Blood urea nitrogen
  - potassium - Electrolyte balance
  - sodium - Electrolyte balance
  - platelets - Clotting function
  - inr - Coagulation status
  - egfr - Kidney function estimate
  - cholesterol_total - Cardiovascular risk
  - ldl_cholesterol - "Bad" cholesterol
  - hdl_cholesterol - "Good" cholesterol
  - tsh - Thyroid function

  ## Production Use

  In production, configure `:medlum_llm` to use `MedOntologyEx.LOINC`:

      config :medlum_llm,
        loinc_module: MedOntologyEx.LOINC

  """

  @lab_tests %{
    "hemoglobin_a1c" => %{
      loinc: "4548-4",
      name: "Hemoglobin A1c",
      unit: "%",
      reference_range: %{low: 4.0, high: 5.6},
      physiological_limits: %{min: 2.0, max: 20.0},
      critical: %{low: 3.0, high: 14.0}
    },
    "glucose" => %{
      loinc: "2345-7",
      name: "Glucose",
      unit: "mg/dL",
      reference_range: %{low: 70, high: 100},
      physiological_limits: %{min: 20, max: 600},
      critical: %{low: 40, high: 400}
    },
    "hemoglobin" => %{
      loinc: "718-7",
      name: "Hemoglobin",
      unit: "g/dL",
      # Adult range
      reference_range: %{low: 12.0, high: 17.5},
      physiological_limits: %{min: 3.0, max: 25.0},
      critical: %{low: 7.0, high: 20.0}
    },
    "wbc" => %{
      loinc: "6690-2",
      name: "White Blood Cell Count",
      unit: "K/uL",
      reference_range: %{low: 4.5, high: 11.0},
      physiological_limits: %{min: 0.1, max: 100.0},
      critical: %{low: 2.0, high: 30.0}
    },
    "creatinine" => %{
      loinc: "2160-0",
      name: "Creatinine",
      unit: "mg/dL",
      reference_range: %{low: 0.7, high: 1.3},
      physiological_limits: %{min: 0.1, max: 20.0},
      critical: %{low: 0.3, high: 10.0}
    },
    "bun" => %{
      loinc: "3094-0",
      name: "Blood Urea Nitrogen",
      unit: "mg/dL",
      reference_range: %{low: 7, high: 20},
      physiological_limits: %{min: 1, max: 150},
      critical: %{low: 5, high: 100}
    },
    "potassium" => %{
      loinc: "2823-3",
      name: "Potassium",
      unit: "mEq/L",
      reference_range: %{low: 3.5, high: 5.0},
      physiological_limits: %{min: 1.5, max: 10.0},
      critical: %{low: 2.5, high: 6.5}
    },
    "sodium" => %{
      loinc: "2951-2",
      name: "Sodium",
      unit: "mEq/L",
      reference_range: %{low: 136, high: 145},
      physiological_limits: %{min: 100, max: 180},
      critical: %{low: 120, high: 160}
    },
    "platelets" => %{
      loinc: "777-3",
      name: "Platelets",
      unit: "K/uL",
      reference_range: %{low: 150, high: 400},
      physiological_limits: %{min: 10, max: 1000},
      critical: %{low: 50, high: 800}
    },
    "inr" => %{
      loinc: "6301-6",
      name: "INR",
      unit: "ratio",
      # Non-anticoagulated
      reference_range: %{low: 0.9, high: 1.1},
      physiological_limits: %{min: 0.5, max: 10.0},
      critical: %{low: 0.8, high: 5.0}
    },
    "egfr" => %{
      loinc: "33914-3",
      name: "Estimated GFR",
      unit: "mL/min",
      reference_range: %{low: 90, high: 120},
      physiological_limits: %{min: 0, max: 200},
      critical: %{low: 15, high: nil}
    },
    "cholesterol_total" => %{
      loinc: "2093-3",
      name: "Total Cholesterol",
      unit: "mg/dL",
      # Desirable <200
      reference_range: %{low: 0, high: 200},
      physiological_limits: %{min: 50, max: 500},
      critical: %{low: 100, high: 400}
    },
    "ldl_cholesterol" => %{
      loinc: "2089-1",
      name: "LDL Cholesterol",
      unit: "mg/dL",
      # Optimal <100
      reference_range: %{low: 0, high: 100},
      physiological_limits: %{min: 20, max: 400},
      critical: %{low: nil, high: 190}
    },
    "hdl_cholesterol" => %{
      loinc: "2085-9",
      name: "HDL Cholesterol",
      unit: "mg/dL",
      # Higher is better
      reference_range: %{low: 40, high: 100},
      physiological_limits: %{min: 10, max: 150},
      critical: %{low: 20, high: nil}
    },
    "tsh" => %{
      loinc: "3016-3",
      name: "TSH",
      unit: "mIU/L",
      reference_range: %{low: 0.4, high: 4.0},
      physiological_limits: %{min: 0.01, max: 100.0},
      critical: %{low: 0.1, high: 20.0}
    }
  }

  @doc """
  Look up lab test in LOINC.

  Returns the LOINC code for a lab test name.

  ## Examples

      iex> LOINCStub.lookup("hemoglobin_a1c")
      {:ok, "4548-4"}

      iex> LOINCStub.lookup("unknown_test")
      {:error, :not_found}

  """
  @spec lookup(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def lookup(test_name) do
    normalized = normalize_test_name(test_name)

    case Map.fetch(@lab_tests, normalized) do
      {:ok, info} -> {:ok, info.loinc}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Get reference range for a lab test.

  Returns the typical reference range for a given LOINC code.
  Demographics may be used in the future for age/sex-specific ranges.

  ## Examples

      iex> LOINCStub.reference_range("4548-4")
      {:ok, %{low: 4.0, high: 5.6, critical_low: 3.0, critical_high: 14.0}}

  """
  @spec reference_range(String.t(), map()) :: {:ok, map()} | {:error, :no_range_data}
  def reference_range(loinc_code, _demographics \\ %{}) do
    case find_by_loinc(loinc_code) do
      nil ->
        {:error, :no_range_data}

      %{reference_range: range, critical: critical} ->
        {:ok, Map.merge(range, %{critical_low: critical[:low], critical_high: critical[:high]})}
    end
  end

  @doc """
  Get physiological limits (impossible values outside this range).

  Returns the physiologically possible range for a given LOINC code.
  Values outside this range are likely data entry errors or impossible.

  ## Examples

      iex> LOINCStub.physiological_limits("4548-4")
      {:ok, %{min: 2.0, max: 20.0}}

  """
  @spec physiological_limits(String.t()) :: {:ok, map()} | {:error, :no_limit_data}
  def physiological_limits(loinc_code) do
    case find_by_loinc(loinc_code) do
      nil -> {:error, :no_limit_data}
      %{physiological_limits: limits} -> {:ok, limits}
    end
  end

  @doc """
  Get expected unit for lab test.

  Returns the standard unit for a given LOINC code.

  ## Examples

      iex> LOINCStub.expected_unit("4548-4")
      {:ok, "%"}

      iex> LOINCStub.expected_unit("2345-7")
      {:ok, "mg/dL"}

  """
  @spec expected_unit(String.t()) :: {:ok, String.t()} | {:error, :no_unit_data}
  def expected_unit(loinc_code) do
    case find_by_loinc(loinc_code) do
      nil -> {:error, :no_unit_data}
      %{unit: unit} -> {:ok, unit}
    end
  end

  defp normalize_test_name(name) do
    name
    |> String.downcase()
    |> String.replace(" ", "_")
    |> String.replace("-", "_")
  end

  defp find_by_loinc(loinc_code) do
    @lab_tests
    |> Enum.find(fn {_, v} -> v.loinc == loinc_code end)
    |> case do
      nil -> nil
      {_, info} -> info
    end
  end
end
