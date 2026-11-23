defmodule ClinicalNerEx.Types.Temporal do
  @moduledoc """
  Temporal expression attributes.

  Represents the structured attributes extracted from a temporal
  expression in clinical text.

  ## Fields

  - `temporal_type` - Type of temporal expression
  - `value` - The parsed value (Date, Time, DateTime, number, or string)
  - `unit` - Unit for durations (days, weeks, months, etc.)
  - `relation` - Temporal relation (start, end, occurrence)

  ## Temporal Types

  - `:date` - A specific date (e.g., "1/15/2026")
  - `:time` - A specific time (e.g., "3:00 PM")
  - `:datetime` - A specific date and time
  - `:duration` - A span of time (e.g., "2 weeks")
  - `:relative` - A relative reference (e.g., "yesterday", "next week")

  ## Examples

      iex> %ClinicalNerEx.Types.Temporal{
      ...>   temporal_type: :date,
      ...>   value: ~D[2026-01-15],
      ...>   relation: "start"
      ...> }

      iex> %ClinicalNerEx.Types.Temporal{
      ...>   temporal_type: :duration,
      ...>   value: 14,
      ...>   unit: "days"
      ...> }
  """

  @type temporal_type :: :date | :time | :datetime | :duration | :relative

  @type t :: %__MODULE__{
          temporal_type: temporal_type() | nil,
          value: Date.t() | Time.t() | DateTime.t() | number() | String.t() | nil,
          unit: String.t() | nil,
          relation: String.t() | nil
        }

  defstruct [
    :temporal_type,
    :value,
    :unit,
    :relation
  ]

  @doc """
  Creates a new Temporal struct from a map of attributes.

  ## Examples

      iex> ClinicalNerEx.Types.Temporal.new(%{temporal_type: :duration, value: 7, unit: "days"})
      %ClinicalNerEx.Types.Temporal{temporal_type: :duration, value: 7, unit: "days"}
  """
  @spec new(map()) :: t()
  def new(attrs \\ %{}) when is_map(attrs) do
    struct(__MODULE__, attrs)
  end

  @doc """
  Returns valid temporal types.
  """
  @spec valid_temporal_types() :: [temporal_type()]
  def valid_temporal_types do
    [:date, :time, :datetime, :duration, :relative]
  end
end
