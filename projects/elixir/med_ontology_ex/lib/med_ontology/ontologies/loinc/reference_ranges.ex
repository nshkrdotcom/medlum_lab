defmodule MedOntology.LOINC.ReferenceRanges do
  @moduledoc """
  Default reference ranges for common LOINC codes.

  These are general adult reference ranges and should be
  supplemented with institution-specific ranges.

  **Note:** Reference ranges can vary by:
  - Age and sex
  - Laboratory method
  - Institution

  ## Examples

      # Get reference range
      iex> MedOntology.LOINC.ReferenceRanges.get("4548-4")
      {:ok, %{name: "Hemoglobin A1c", low: 4.0, high: 5.6, unit: "%"}}

      # Evaluate a lab value
      iex> MedOntology.LOINC.ReferenceRanges.evaluate("4548-4", 6.8)
      {:ok, :high}

      iex> MedOntology.LOINC.ReferenceRanges.evaluate("4548-4", 5.0)
      {:ok, :normal}

  ## Included Labs

  The following categories of lab tests have reference ranges defined:

    * **Glucose and A1c** - Glucose, Hemoglobin A1c
    * **Renal Function** - Creatinine, BUN, eGFR
    * **Complete Blood Count** - Hemoglobin, Hematocrit, WBC, Platelets
    * **Electrolytes** - Sodium, Potassium, Chloride, CO2
    * **Liver Function** - ALT, AST, ALP, Bilirubin
    * **Lipid Panel** - Total Cholesterol, HDL, LDL, Triglycerides
    * **Thyroid** - TSH, Free T4

  """

  @default_ranges %{
    # Glucose and A1c
    "2345-7" => %{
      name: "Glucose",
      low: 70,
      high: 100,
      unit: "mg/dL",
      critical_low: 40,
      critical_high: 500
    },
    "4548-4" => %{
      name: "Hemoglobin A1c",
      low: 4.0,
      high: 5.6,
      unit: "%",
      critical_high: 14.0
    },

    # Renal function
    "2160-0" => %{
      name: "Creatinine",
      low: 0.7,
      high: 1.3,
      unit: "mg/dL",
      critical_high: 10.0
    },
    "3094-0" => %{
      name: "BUN",
      low: 7,
      high: 20,
      unit: "mg/dL",
      critical_high: 100
    },
    "33914-3" => %{
      name: "eGFR",
      low: 90,
      high: 120,
      unit: "mL/min/1.73m2"
    },

    # Complete blood count
    "718-7" => %{
      name: "Hemoglobin",
      low: 12.0,
      high: 16.0,
      unit: "g/dL",
      critical_low: 7.0
    },
    "4544-3" => %{
      name: "Hematocrit",
      low: 36,
      high: 48,
      unit: "%",
      critical_low: 20
    },
    "6690-2" => %{
      name: "WBC",
      low: 4.5,
      high: 11.0,
      unit: "10^3/uL",
      critical_high: 30.0
    },
    "777-3" => %{
      name: "Platelets",
      low: 150,
      high: 400,
      unit: "10^3/uL",
      critical_low: 20,
      critical_high: 1000
    },

    # Electrolytes
    "2951-2" => %{
      name: "Sodium",
      low: 136,
      high: 145,
      unit: "mmol/L",
      critical_low: 120,
      critical_high: 160
    },
    "2823-3" => %{
      name: "Potassium",
      low: 3.5,
      high: 5.0,
      unit: "mmol/L",
      critical_low: 2.5,
      critical_high: 6.5
    },
    "2075-0" => %{
      name: "Chloride",
      low: 96,
      high: 106,
      unit: "mmol/L"
    },
    "2028-9" => %{
      name: "CO2",
      low: 22,
      high: 28,
      unit: "mmol/L"
    },

    # Liver function
    "1742-6" => %{
      name: "ALT",
      low: 7,
      high: 56,
      unit: "U/L"
    },
    "1920-8" => %{
      name: "AST",
      low: 10,
      high: 40,
      unit: "U/L"
    },
    "6768-6" => %{
      name: "ALP",
      low: 44,
      high: 147,
      unit: "U/L"
    },
    "1975-2" => %{
      name: "Bilirubin Total",
      low: 0.1,
      high: 1.2,
      unit: "mg/dL"
    },

    # Lipid panel
    "2093-3" => %{
      name: "Cholesterol Total",
      low: 0,
      high: 200,
      unit: "mg/dL"
    },
    "2085-9" => %{
      name: "HDL Cholesterol",
      low: 40,
      high: 999,
      unit: "mg/dL"
    },
    "13457-7" => %{
      name: "LDL Cholesterol Direct",
      low: 0,
      high: 100,
      unit: "mg/dL"
    },
    "2571-8" => %{
      name: "Triglycerides",
      low: 0,
      high: 150,
      unit: "mg/dL"
    },

    # Thyroid
    "3016-3" => %{
      name: "TSH",
      low: 0.4,
      high: 4.0,
      unit: "mIU/L"
    },
    "3051-0" => %{
      name: "T4 Free",
      low: 0.8,
      high: 1.8,
      unit: "ng/dL"
    }
  }

  @doc """
  Get reference range for a LOINC code.

  Returns the reference range including low, high, unit, and optional
  critical values.

  ## Examples

      iex> MedOntology.LOINC.ReferenceRanges.get("4548-4")
      {:ok, %{name: "Hemoglobin A1c", low: 4.0, high: 5.6, unit: "%", critical_high: 14.0}}

      iex> MedOntology.LOINC.ReferenceRanges.get("unknown-code")
      {:error, :not_available}

  """
  @spec get(String.t()) :: {:ok, map()} | {:error, :not_available}
  def get(loinc_code) do
    case Map.get(@default_ranges, loinc_code) do
      nil -> {:error, :not_available}
      range -> {:ok, range}
    end
  end

  @doc """
  Evaluate a lab value against reference range.

  ## Returns

    * `:normal` - Within reference range
    * `:low` - Below low threshold
    * `:high` - Above high threshold
    * `:critical_low` - Below critical low threshold
    * `:critical_high` - Above critical high threshold

  ## Examples

      iex> MedOntology.LOINC.ReferenceRanges.evaluate("4548-4", 6.8)
      {:ok, :high}

      iex> MedOntology.LOINC.ReferenceRanges.evaluate("4548-4", 5.0)
      {:ok, :normal}

      iex> MedOntology.LOINC.ReferenceRanges.evaluate("2345-7", 35)
      {:ok, :critical_low}

      iex> MedOntology.LOINC.ReferenceRanges.evaluate("unknown", 100)
      {:error, :not_available}

  """
  @spec evaluate(String.t(), number()) :: {:ok, atom()} | {:error, :not_available}
  def evaluate(loinc_code, value) do
    case get(loinc_code) do
      {:ok, range} -> {:ok, determine_status(range, value)}
      error -> error
    end
  end

  defp determine_status(range, value) do
    cond do
      critical_low?(range, value) -> :critical_low
      critical_high?(range, value) -> :critical_high
      value < range[:low] -> :low
      value > range[:high] -> :high
      true -> :normal
    end
  end

  defp critical_low?(range, value), do: range[:critical_low] && value < range[:critical_low]
  defp critical_high?(range, value), do: range[:critical_high] && value > range[:critical_high]

  @doc """
  Get all reference ranges.

  Returns a map of LOINC code to reference range data.

  ## Examples

      iex> ranges = MedOntology.LOINC.ReferenceRanges.all()
      iex> Map.has_key?(ranges, "2345-7")
      true

  """
  @spec all() :: map()
  def all, do: @default_ranges

  @doc """
  Get codes with defined reference ranges.

  Returns a list of LOINC codes that have reference ranges available.

  ## Examples

      iex> codes = MedOntology.LOINC.ReferenceRanges.available_codes()
      iex> "2345-7" in codes
      true

  """
  @spec available_codes() :: [String.t()]
  def available_codes, do: Map.keys(@default_ranges)

  @doc """
  Check if a reference range is available for a LOINC code.

  ## Examples

      iex> MedOntology.LOINC.ReferenceRanges.available?("2345-7")
      true

      iex> MedOntology.LOINC.ReferenceRanges.available?("unknown")
      false

  """
  @spec available?(String.t()) :: boolean()
  def available?(loinc_code) do
    Map.has_key?(@default_ranges, loinc_code)
  end

  @doc """
  Get reference ranges by category.

  Returns reference ranges grouped by clinical category.

  ## Examples

      iex> MedOntology.LOINC.ReferenceRanges.by_category(:electrolytes)
      %{
        "2951-2" => %{name: "Sodium", low: 136, high: 145, unit: "mmol/L", ...},
        "2823-3" => %{name: "Potassium", low: 3.5, high: 5.0, unit: "mmol/L", ...},
        ...
      }

  """
  @spec by_category(atom()) :: map()
  def by_category(category) do
    codes =
      case category do
        :glucose -> ["2345-7", "4548-4"]
        :renal -> ["2160-0", "3094-0", "33914-3"]
        :cbc -> ["718-7", "4544-3", "6690-2", "777-3"]
        :electrolytes -> ["2951-2", "2823-3", "2075-0", "2028-9"]
        :liver -> ["1742-6", "1920-8", "6768-6", "1975-2"]
        :lipids -> ["2093-3", "2085-9", "13457-7", "2571-8"]
        :thyroid -> ["3016-3", "3051-0"]
        _ -> []
      end

    Map.take(@default_ranges, codes)
  end
end
