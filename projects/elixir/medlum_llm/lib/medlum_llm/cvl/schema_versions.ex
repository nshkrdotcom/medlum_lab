defmodule MedlumLlm.CVL.SchemaVersions do
  @moduledoc """
  CVL NLI labeling schema version registry.

  Manages schema versioning for reproducible training data exports. Each version
  defines the exact fields, validation rules, and metadata structure expected
  for NLI classification labels.

  ## Version History

  - **1.0** - Initial schema: verdict + confidence
  - **1.1** - Added evidence_quality assessment field
  - **2.0** - (Future) Added reasoning field with evidence spans

  ## Schema Evolution Rules

  1. New optional fields may be added in minor versions (1.0 -> 1.1)
  2. Required fields or breaking changes require major version bump
  3. Removed fields are preserved in exports for backward compatibility
  4. Field validation rules may be tightened but not loosened

  ## Usage

      # Get current version
      version = MedlumLlm.CVL.SchemaVersions.current_version()
      # => "1.1"

      # Get schema for specific version
      schema = MedlumLlm.CVL.SchemaVersions.schema("1.0")

      # List all available versions
      versions = MedlumLlm.CVL.SchemaVersions.available_versions()
      # => ["1.0", "1.1"]

      # Get field mapping between versions
      mapping = MedlumLlm.CVL.SchemaVersions.field_mapping("1.0", "1.1")
  """

  alias MedlumLlm.CVL.LabelingSchema

  @current_version "1.1"

  @version_registry %{
    "1.0" => %{
      name: "cvl_nli_v1.0",
      released: ~D[2026-01-01],
      status: :stable,
      fields: [:verdict, :confidence],
      description: "Initial schema with verdict and confidence fields"
    },
    "1.1" => %{
      name: "cvl_nli_v1.1",
      released: ~D[2026-01-25],
      status: :stable,
      fields: [:verdict, :confidence, :evidence_quality, :reasoning],
      description: "Added evidence_quality assessment and optional reasoning"
    }
  }

  @type version :: String.t()
  @type schema_info :: %{
          name: String.t(),
          released: Date.t(),
          status: :stable | :deprecated | :experimental,
          fields: [atom()],
          description: String.t()
        }

  @doc """
  Returns the current (latest stable) schema version.

  ## Examples

      iex> MedlumLlm.CVL.SchemaVersions.current_version()
      "1.1"
  """
  @spec current_version() :: version()
  def current_version, do: @current_version

  @doc """
  Returns the schema for a specific version.

  ## Examples

      iex> schema = MedlumLlm.CVL.SchemaVersions.schema("1.0")
      iex> schema.version
      "1.0"

      iex> schema = MedlumLlm.CVL.SchemaVersions.schema("1.1")
      iex> length(schema.fields)
      4
  """
  @spec schema(version()) :: Anvil.Schema.t() | nil
  def schema(version) do
    case Map.get(@version_registry, version) do
      nil -> nil
      info -> build_schema_for_version(version, info)
    end
  end

  @doc """
  Returns schema information for a version.

  ## Examples

      iex> info = MedlumLlm.CVL.SchemaVersions.schema_info("1.0")
      iex> info.status
      :stable
  """
  @spec schema_info(version()) :: schema_info() | nil
  def schema_info(version), do: Map.get(@version_registry, version)

  @doc """
  Returns a list of all available schema versions.

  ## Examples

      iex> MedlumLlm.CVL.SchemaVersions.available_versions()
      ["1.0", "1.1"]
  """
  @spec available_versions() :: [version()]
  def available_versions do
    @version_registry
    |> Map.keys()
    |> Enum.sort(&version_compare/2)
  end

  @doc """
  Returns a list of stable schema versions.
  """
  @spec stable_versions() :: [version()]
  def stable_versions do
    @version_registry
    |> Enum.filter(fn {_v, info} -> info.status == :stable end)
    |> Enum.map(fn {v, _info} -> v end)
    |> Enum.sort(&version_compare/2)
  end

  @doc """
  Checks if a version is valid.

  ## Examples

      iex> MedlumLlm.CVL.SchemaVersions.valid_version?("1.1")
      true

      iex> MedlumLlm.CVL.SchemaVersions.valid_version?("9.9")
      false
  """
  @spec valid_version?(version()) :: boolean()
  def valid_version?(version), do: Map.has_key?(@version_registry, version)

  @doc """
  Returns the field mapping between two schema versions.

  Useful for migrating data between versions or understanding what changed.

  ## Examples

      iex> mapping = MedlumLlm.CVL.SchemaVersions.field_mapping("1.0", "1.1")
      iex> mapping.added
      [:evidence_quality, :reasoning]
  """
  @spec field_mapping(version(), version()) :: map() | {:error, :invalid_version}
  def field_mapping(from_version, to_version) do
    with {:ok, from_info} <- get_version_info(from_version),
         {:ok, to_info} <- get_version_info(to_version) do
      from_fields = MapSet.new(from_info.fields)
      to_fields = MapSet.new(to_info.fields)

      %{
        from_version: from_version,
        to_version: to_version,
        unchanged: MapSet.intersection(from_fields, to_fields) |> MapSet.to_list(),
        added: MapSet.difference(to_fields, from_fields) |> MapSet.to_list(),
        removed: MapSet.difference(from_fields, to_fields) |> MapSet.to_list()
      }
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates that a label matches the expected schema version.

  ## Examples

      iex> label = %{"verdict" => "ENTAILMENT", "confidence" => 4}
      iex> MedlumLlm.CVL.SchemaVersions.validate_label(label, "1.0")
      :ok

      iex> label = %{"verdict" => "INVALID"}
      iex> MedlumLlm.CVL.SchemaVersions.validate_label(label, "1.0")
      {:error, [%{field: "verdict", error: "must be one of: ENTAILMENT, CONTRADICTION, NEUTRAL"}]}
  """
  @spec validate_label(map(), version()) :: :ok | {:error, [map()]}
  def validate_label(label, version) do
    case schema(version) do
      nil ->
        {:error, :invalid_version}

      schema ->
        case Anvil.Schema.validate(schema, label) do
          {:ok, _} -> :ok
          {:error, errors} -> {:error, errors}
        end
    end
  end

  @doc """
  Returns the changelog between two versions.
  """
  @spec changelog(version(), version()) :: map() | {:error, :invalid_version}
  def changelog(from_version, to_version) do
    with {:ok, from_info} <- get_version_info(from_version),
         {:ok, to_info} <- get_version_info(to_version) do
      mapping = field_mapping(from_version, to_version)

      %{
        from: %{
          version: from_version,
          released: from_info.released,
          description: from_info.description
        },
        to: %{
          version: to_version,
          released: to_info.released,
          description: to_info.description
        },
        changes: mapping
      }
    end
  end

  # Private functions

  defp build_schema_for_version("1.0", _info) do
    LabelingSchema.schema(version: "1.0", include_reasoning: false)
  end

  defp build_schema_for_version("1.1", _info) do
    LabelingSchema.schema(version: "1.1", include_reasoning: true)
  end

  defp build_schema_for_version(version, _info) do
    # Default to current schema structure for unknown versions
    LabelingSchema.schema(version: version)
  end

  defp get_version_info(version) do
    case Map.get(@version_registry, version) do
      nil -> {:error, :invalid_version}
      info -> {:ok, info}
    end
  end

  defp version_compare(v1, v2) do
    v1_parts = String.split(v1, ".") |> Enum.map(&String.to_integer/1)
    v2_parts = String.split(v2, ".") |> Enum.map(&String.to_integer/1)
    v1_parts <= v2_parts
  end
end
