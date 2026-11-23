defmodule ClinicalNerEx.Types.Diagnosis do
  @moduledoc """
  Diagnosis entity attributes.

  Represents the structured attributes extracted from a diagnosis,
  condition, or symptom mention in clinical text.

  ## Fields

  - `condition` - Name of the disease, disorder, or condition
  - `status` - Current status of the condition
  - `severity` - Severity level
  - `body_site` - Anatomical location
  - `laterality` - Left, right, or bilateral
  - `onset` - When the condition started

  ## Status Values

  - `:active` - Currently present condition
  - `:resolved` - Previously present, now resolved
  - `:historical` - Past medical history
  - `:suspected` - Under consideration
  - `:ruled_out` - Excluded from differential

  ## Severity Values

  - `:mild` - Mild severity
  - `:moderate` - Moderate severity
  - `:severe` - Severe

  ## Laterality Values

  - `:left` - Left side
  - `:right` - Right side
  - `:bilateral` - Both sides

  ## Examples

      iex> %ClinicalNerEx.Types.Diagnosis{
      ...>   condition: "Type 2 diabetes mellitus",
      ...>   status: :active,
      ...>   severity: :moderate
      ...> }
  """

  @type status :: :active | :resolved | :historical | :suspected | :ruled_out
  @type severity :: :mild | :moderate | :severe | nil
  @type laterality :: :left | :right | :bilateral | nil

  @type t :: %__MODULE__{
          condition: String.t() | nil,
          status: status(),
          severity: severity(),
          body_site: String.t() | nil,
          laterality: laterality(),
          onset: Date.t() | String.t() | nil
        }

  defstruct [
    :condition,
    :severity,
    :body_site,
    :laterality,
    :onset,
    status: :active
  ]

  @doc """
  Creates a new Diagnosis struct from a map of attributes.

  ## Examples

      iex> ClinicalNerEx.Types.Diagnosis.new(%{condition: "hypertension", status: :active})
      %ClinicalNerEx.Types.Diagnosis{condition: "hypertension", status: :active}
  """
  @spec new(map()) :: t()
  def new(attrs \\ %{}) when is_map(attrs) do
    struct(__MODULE__, attrs)
  end

  @doc """
  Returns valid status values.
  """
  @spec valid_statuses() :: [status()]
  def valid_statuses do
    [:active, :resolved, :historical, :suspected, :ruled_out]
  end

  @doc """
  Returns valid severity values.
  """
  @spec valid_severities() :: [severity()]
  def valid_severities do
    [:mild, :moderate, :severe, nil]
  end

  @doc """
  Returns valid laterality values.
  """
  @spec valid_lateralities() :: [laterality()]
  def valid_lateralities do
    [:left, :right, :bilateral, nil]
  end
end
