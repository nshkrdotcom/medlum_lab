defmodule ClinicalNerEx.Types.Procedure do
  @moduledoc """
  Procedure entity attributes.

  Represents the structured attributes extracted from a medical
  procedure mention in clinical text.

  ## Fields

  - `procedure_name` - Name of the procedure
  - `body_site` - Anatomical location where performed
  - `method` - How the procedure was performed (percutaneous, open, etc.)
  - `device` - Any device used
  - `timestamp` - When the procedure was performed
  - `status` - Status of the procedure

  ## Status Values

  - `:planned` - Scheduled for the future
  - `:completed` - Already performed
  - `:cancelled` - Cancelled

  ## Examples

      iex> %ClinicalNerEx.Types.Procedure{
      ...>   procedure_name: "Coronary angiography",
      ...>   body_site: "heart",
      ...>   method: "percutaneous",
      ...>   status: :completed
      ...> }
  """

  @type status :: :planned | :completed | :cancelled

  @type t :: %__MODULE__{
          procedure_name: String.t() | nil,
          body_site: String.t() | nil,
          method: String.t() | nil,
          device: String.t() | nil,
          timestamp: Date.t() | DateTime.t() | nil,
          status: status()
        }

  defstruct [
    :procedure_name,
    :body_site,
    :method,
    :device,
    :timestamp,
    status: :completed
  ]

  @doc """
  Creates a new Procedure struct from a map of attributes.

  ## Examples

      iex> ClinicalNerEx.Types.Procedure.new(%{procedure_name: "colonoscopy", status: :planned})
      %ClinicalNerEx.Types.Procedure{procedure_name: "colonoscopy", status: :planned}
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
    [:planned, :completed, :cancelled]
  end
end
