defmodule ClinicalNerEx.Types.LabValue do
  @moduledoc """
  Lab value entity attributes.

  Represents the structured attributes extracted from a laboratory
  test result mention in clinical text.

  ## Fields

  - `lab_name` - Name of the laboratory test
  - `value` - Numeric result value
  - `unit` - Unit of measurement
  - `reference_low` - Lower bound of normal range
  - `reference_high` - Upper bound of normal range
  - `abnormal_flag` - Abnormality indicator (H, L, C for critical)
  - `timestamp` - When the test was collected
  - `specimen` - Specimen type (blood, urine, etc.)

  ## Examples

      iex> %ClinicalNerEx.Types.LabValue{
      ...>   lab_name: "Hemoglobin A1c",
      ...>   value: 6.5,
      ...>   unit: "%",
      ...>   reference_low: 4.0,
      ...>   reference_high: 5.6,
      ...>   abnormal_flag: "H"
      ...> }
  """

  @type t :: %__MODULE__{
          lab_name: String.t() | nil,
          value: number() | nil,
          unit: String.t() | nil,
          reference_low: number() | nil,
          reference_high: number() | nil,
          abnormal_flag: String.t() | nil,
          timestamp: Date.t() | DateTime.t() | nil,
          specimen: String.t() | nil
        }

  defstruct [
    :lab_name,
    :value,
    :unit,
    :reference_low,
    :reference_high,
    :abnormal_flag,
    :timestamp,
    :specimen
  ]

  @doc """
  Creates a new LabValue struct from a map of attributes.

  ## Examples

      iex> ClinicalNerEx.Types.LabValue.new(%{lab_name: "Glucose", value: 95, unit: "mg/dL"})
      %ClinicalNerEx.Types.LabValue{lab_name: "Glucose", value: 95, unit: "mg/dL"}
  """
  @spec new(map()) :: t()
  def new(attrs \\ %{}) when is_map(attrs) do
    struct(__MODULE__, attrs)
  end
end
