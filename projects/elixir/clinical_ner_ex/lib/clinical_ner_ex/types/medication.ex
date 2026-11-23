defmodule ClinicalNerEx.Types.Medication do
  @moduledoc """
  Medication entity attributes.

  Represents the structured attributes extracted from a medication mention
  in clinical text.

  ## Fields

  - `drug_name` - Generic or brand name of the medication
  - `dose` - Numeric dose value
  - `dose_unit` - Unit of measurement (mg, mcg, mL, etc.)
  - `frequency` - How often taken (BID, daily, q8h, etc.)
  - `route` - Administration route (PO, IV, SC, topical, etc.)
  - `duration` - Length of therapy (7 days, 2 weeks, etc.)
  - `form` - Drug formulation (tablet, capsule, suspension, etc.)
  - `strength` - Concentration (500mg/5mL)
  - `indication` - Reason for medication
  - `prn` - Whether medication is "as needed"

  ## Examples

      iex> %ClinicalNerEx.Types.Medication{
      ...>   drug_name: "metformin",
      ...>   dose: 500,
      ...>   dose_unit: "mg",
      ...>   frequency: "BID",
      ...>   route: "PO"
      ...> }
  """

  @type t :: %__MODULE__{
          drug_name: String.t() | nil,
          dose: number() | nil,
          dose_unit: String.t() | nil,
          frequency: String.t() | nil,
          route: String.t() | nil,
          duration: String.t() | nil,
          form: String.t() | nil,
          strength: String.t() | nil,
          indication: String.t() | nil,
          prn: boolean()
        }

  defstruct [
    :drug_name,
    :dose,
    :dose_unit,
    :frequency,
    :route,
    :duration,
    :form,
    :strength,
    :indication,
    prn: false
  ]

  @doc """
  Creates a new Medication struct from a map of attributes.

  ## Examples

      iex> ClinicalNerEx.Types.Medication.new(%{drug_name: "aspirin", dose: 81, dose_unit: "mg"})
      %ClinicalNerEx.Types.Medication{drug_name: "aspirin", dose: 81, dose_unit: "mg", prn: false}
  """
  @spec new(map()) :: t()
  def new(attrs \\ %{}) when is_map(attrs) do
    struct(__MODULE__, attrs)
  end
end
