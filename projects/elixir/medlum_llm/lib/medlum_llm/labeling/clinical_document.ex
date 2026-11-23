defmodule MedlumLlm.Labeling.ClinicalDocument do
  @moduledoc """
  Types and validation for clinical document payloads.

  Clinical documents represent the source materials used in CVL verification,
  including discharge summaries, lab reports, consultation notes, and imaging
  reports. Each document may contain ontology codes from standard medical
  terminologies (SNOMED-CT, ICD-10, RxNorm, LOINC).

  ## Document Types

  - `:discharge_summary` - Hospital discharge documentation
  - `:lab_report` - Laboratory test results
  - `:consultation` - Specialist consultation notes
  - `:imaging` - Radiology and imaging reports
  - `:medication_list` - Current medication listings
  - `:progress_note` - Clinical progress notes

  ## Example

      iex> doc = %{
      ...>   type: :discharge_summary,
      ...>   content: "Patient discharged on metformin 500mg BID...",
      ...>   date: ~D[2026-01-15],
      ...>   provider_type: "endocrinology",
      ...>   ontology_codes: %{
      ...>     snomed_ct: ["44054006"],
      ...>     icd10: ["E11.9"],
      ...>     rxnorm: ["861004"],
      ...>     loinc: []
      ...>   }
      ...> }
      iex> {:ok, _validated} = MedlumLlm.Labeling.ClinicalDocument.validate(doc)

  """

  @typedoc """
  Clinical document type identifier.

  Categorizes the source and purpose of the clinical document.
  """
  @type document_type ::
          :discharge_summary
          | :lab_report
          | :consultation
          | :imaging
          | :medication_list
          | :progress_note

  @typedoc """
  Medical ontology code annotations.

  Standard medical terminologies used for semantic annotation:
  - `snomed_ct` - SNOMED Clinical Terms (findings, disorders, procedures)
  - `icd10` - ICD-10-CM diagnosis codes
  - `rxnorm` - RxNorm medication codes
  - `loinc` - LOINC lab test codes
  """
  @type ontology_codes :: %{
          snomed_ct: [String.t()],
          icd10: [String.t()],
          rxnorm: [String.t()],
          loinc: [String.t()]
        }

  @typedoc """
  Clinical document with content and metadata.

  Contains the document text, type classification, date, provider type,
  and ontology code annotations.
  """
  @type t :: %{
          type: document_type(),
          content: String.t(),
          date: Date.t() | nil,
          provider_type: String.t() | nil,
          ontology_codes: ontology_codes()
        }

  @document_types [
    :discharge_summary,
    :lab_report,
    :consultation,
    :imaging,
    :medication_list,
    :progress_note
  ]

  @ontology_keys [:snomed_ct, :icd10, :rxnorm, :loinc]

  @doc """
  Returns the list of valid document types.

  ## Examples

      iex> MedlumLlm.Labeling.ClinicalDocument.document_types()
      [:discharge_summary, :lab_report, :consultation, :imaging, :medication_list, :progress_note]

  """
  @spec document_types() :: [document_type()]
  def document_types, do: @document_types

  @doc """
  Checks if an atom is a valid document type.

  ## Examples

      iex> MedlumLlm.Labeling.ClinicalDocument.valid_document_type?(:discharge_summary)
      true

      iex> MedlumLlm.Labeling.ClinicalDocument.valid_document_type?(:unknown)
      false

  """
  @spec valid_document_type?(atom()) :: boolean()
  def valid_document_type?(type) when is_atom(type), do: type in @document_types
  def valid_document_type?(_), do: false

  @doc """
  Returns the list of supported ontology code keys.

  ## Examples

      iex> MedlumLlm.Labeling.ClinicalDocument.ontology_keys()
      [:snomed_ct, :icd10, :rxnorm, :loinc]

  """
  @spec ontology_keys() :: [atom()]
  def ontology_keys, do: @ontology_keys

  @doc """
  Validates a clinical document map.

  Checks that all required keys are present and values have correct types:
  - `type` must be a valid document type atom
  - `content` must be a non-empty string
  - `date` must be nil or a Date struct
  - `provider_type` must be nil or a string
  - `ontology_codes` must contain all ontology keys with string lists

  ## Examples

      iex> doc = %{
      ...>   type: :lab_report,
      ...>   content: "HbA1c: 7.2%",
      ...>   date: nil,
      ...>   provider_type: "laboratory",
      ...>   ontology_codes: %{snomed_ct: [], icd10: [], rxnorm: [], loinc: ["4548-4"]}
      ...> }
      iex> {:ok, validated} = MedlumLlm.Labeling.ClinicalDocument.validate(doc)
      iex> validated.type
      :lab_report

      iex> MedlumLlm.Labeling.ClinicalDocument.validate(%{type: :invalid})
      {:error, {:invalid_document_type, :invalid}}

  """
  @spec validate(map()) :: {:ok, t()} | {:error, term()}
  def validate(map) when is_map(map) do
    with {:ok, type} <- validate_type_field(map),
         {:ok, content} <- validate_content_field(map),
         {:ok, date} <- validate_date_field(map),
         {:ok, provider_type} <- validate_provider_type_field(map),
         {:ok, codes} <- validate_ontology_codes_field(map) do
      {:ok,
       %{
         type: type,
         content: content,
         date: date,
         provider_type: provider_type,
         ontology_codes: codes
       }}
    end
  end

  def validate(_), do: {:error, :not_a_map}

  @doc """
  Validates a clinical document map, raising on invalid input.

  ## Examples

      iex> doc = %{
      ...>   type: :consultation,
      ...>   content: "Follow-up visit...",
      ...>   date: ~D[2026-01-20],
      ...>   provider_type: "cardiology",
      ...>   ontology_codes: %{snomed_ct: [], icd10: [], rxnorm: [], loinc: []}
      ...> }
      iex> validated = MedlumLlm.Labeling.ClinicalDocument.validate!(doc)
      iex> validated.type
      :consultation

  """
  @spec validate!(map()) :: t()
  def validate!(map) do
    case validate(map) do
      {:ok, doc} -> doc
      {:error, reason} -> raise ArgumentError, "Invalid clinical document: #{inspect(reason)}"
    end
  end

  @doc """
  Serializes a clinical document to a map suitable for JSON encoding.

  Converts atoms to strings and dates to ISO8601 format.

  ## Examples

      iex> doc = %{
      ...>   type: :discharge_summary,
      ...>   content: "Patient discharged...",
      ...>   date: ~D[2026-01-15],
      ...>   provider_type: "internal_medicine",
      ...>   ontology_codes: %{snomed_ct: ["44054006"], icd10: ["E11.9"], rxnorm: [], loinc: []}
      ...> }
      iex> serialized = MedlumLlm.Labeling.ClinicalDocument.serialize(doc)
      iex> serialized["type"]
      "discharge_summary"
      iex> serialized["date"]
      "2026-01-15"

  """
  @spec serialize(t()) :: map()
  def serialize(doc) do
    %{
      "type" => Atom.to_string(doc.type),
      "content" => doc.content,
      "date" => if(doc.date, do: Date.to_iso8601(doc.date), else: nil),
      "provider_type" => doc.provider_type,
      "ontology_codes" => serialize_ontology_codes(doc.ontology_codes)
    }
  end

  @doc """
  Deserializes a map (from JSON) into a validated clinical document.

  Parses string dates and atom keys.

  ## Examples

      iex> data = %{
      ...>   "type" => "lab_report",
      ...>   "content" => "HbA1c: 7.2%",
      ...>   "date" => "2026-01-14",
      ...>   "provider_type" => "laboratory",
      ...>   "ontology_codes" => %{"loinc" => ["4548-4"], "snomed_ct" => [], "icd10" => [], "rxnorm" => []}
      ...> }
      iex> {:ok, doc} = MedlumLlm.Labeling.ClinicalDocument.deserialize(data)
      iex> doc.type
      :lab_report

  """
  @spec deserialize(map()) :: {:ok, t()} | {:error, term()}
  def deserialize(map) when is_map(map) do
    with {:ok, type} <- parse_type(map),
         {:ok, content} <- parse_content(map),
         {:ok, date} <- parse_date(map),
         {:ok, provider_type} <- parse_provider_type(map),
         {:ok, codes} <- parse_ontology_codes(map) do
      {:ok,
       %{
         type: type,
         content: content,
         date: date,
         provider_type: provider_type,
         ontology_codes: codes
       }}
    end
  end

  def deserialize(_), do: {:error, :not_a_map}

  @doc """
  Creates an empty ontology codes map with all keys initialized to empty lists.

  ## Examples

      iex> MedlumLlm.Labeling.ClinicalDocument.empty_ontology_codes()
      %{snomed_ct: [], icd10: [], rxnorm: [], loinc: []}

  """
  @spec empty_ontology_codes() :: ontology_codes()
  def empty_ontology_codes do
    %{snomed_ct: [], icd10: [], rxnorm: [], loinc: []}
  end

  # Private validation helpers

  defp validate_type_field(map) do
    case Map.fetch(map, :type) do
      {:ok, type} when is_atom(type) ->
        if valid_document_type?(type) do
          {:ok, type}
        else
          {:error, {:invalid_document_type, type}}
        end

      {:ok, other} ->
        {:error, {:invalid_document_type_format, other}}

      :error ->
        {:error, :missing_type}
    end
  end

  defp validate_content_field(map) do
    case Map.fetch(map, :content) do
      {:ok, content} when is_binary(content) and byte_size(content) > 0 ->
        {:ok, content}

      {:ok, ""} ->
        {:error, :empty_content}

      {:ok, other} ->
        {:error, {:invalid_content_type, other}}

      :error ->
        {:error, :missing_content}
    end
  end

  defp validate_date_field(map) do
    case Map.fetch(map, :date) do
      {:ok, nil} -> {:ok, nil}
      {:ok, %Date{} = date} -> {:ok, date}
      {:ok, other} -> {:error, {:invalid_date_type, other}}
      :error -> {:error, :missing_date}
    end
  end

  defp validate_provider_type_field(map) do
    case Map.fetch(map, :provider_type) do
      {:ok, nil} -> {:ok, nil}
      {:ok, provider_type} when is_binary(provider_type) -> {:ok, provider_type}
      {:ok, other} -> {:error, {:invalid_provider_type, other}}
      :error -> {:error, :missing_provider_type}
    end
  end

  defp validate_ontology_codes_field(map) do
    case Map.fetch(map, :ontology_codes) do
      {:ok, codes} when is_map(codes) ->
        validate_all_ontology_keys(codes)

      {:ok, other} ->
        {:error, {:invalid_ontology_codes_type, other}}

      :error ->
        {:error, :missing_ontology_codes}
    end
  end

  defp validate_all_ontology_keys(codes) do
    result =
      Enum.reduce_while(@ontology_keys, {:ok, %{}}, fn key, {:ok, acc} ->
        case Map.fetch(codes, key) do
          {:ok, values} when is_list(values) ->
            if Enum.all?(values, &is_binary/1) do
              {:cont, {:ok, Map.put(acc, key, values)}}
            else
              {:halt, {:error, {:ontology_codes_not_string_list, key}}}
            end

          {:ok, other} ->
            {:halt, {:error, {:invalid_ontology_codes_format, key, other}}}

          :error ->
            {:halt, {:error, {:missing_ontology_key, key}}}
        end
      end)

    result
  end

  defp serialize_ontology_codes(codes) do
    %{
      "snomed_ct" => Map.get(codes, :snomed_ct, []),
      "icd10" => Map.get(codes, :icd10, []),
      "rxnorm" => Map.get(codes, :rxnorm, []),
      "loinc" => Map.get(codes, :loinc, [])
    }
  end

  # Deserialization helpers

  defp parse_type(map) do
    case Map.get(map, "type") || Map.get(map, :type) do
      nil ->
        {:error, :missing_type}

      type when is_atom(type) ->
        if valid_document_type?(type), do: {:ok, type}, else: {:error, {:invalid_document_type, type}}

      type when is_binary(type) ->
        parse_type_string(type)

      other ->
        {:error, {:invalid_document_type_format, other}}
    end
  end

  defp parse_type_string(type) do
    atom = String.to_existing_atom(type)
    if valid_document_type?(atom), do: {:ok, atom}, else: {:error, {:invalid_document_type, type}}
  rescue
    ArgumentError -> {:error, {:invalid_document_type, type}}
  end

  defp parse_content(map) do
    case Map.get(map, "content") || Map.get(map, :content) do
      nil -> {:error, :missing_content}
      "" -> {:error, :empty_content}
      content when is_binary(content) -> {:ok, content}
      other -> {:error, {:invalid_content_type, other}}
    end
  end

  defp parse_date(map) do
    case Map.get(map, "date") || Map.get(map, :date) do
      nil -> {:ok, nil}
      %Date{} = date -> {:ok, date}
      date when is_binary(date) -> parse_date_string(date)
      other -> {:error, {:invalid_date_type, other}}
    end
  end

  defp parse_date_string(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, {:invalid_date_format, date_str}}
    end
  end

  defp parse_provider_type(map) do
    case Map.get(map, "provider_type") || Map.get(map, :provider_type) do
      nil -> {:ok, nil}
      provider when is_binary(provider) -> {:ok, provider}
      other -> {:error, {:invalid_provider_type, other}}
    end
  end

  defp parse_ontology_codes(map) do
    case Map.get(map, "ontology_codes") || Map.get(map, :ontology_codes) do
      nil ->
        {:error, :missing_ontology_codes}

      codes when is_map(codes) ->
        parsed =
          Enum.reduce_while(@ontology_keys, {:ok, %{}}, fn key, {:ok, acc} ->
            string_key = Atom.to_string(key)
            values = Map.get(codes, key) || Map.get(codes, string_key) || []

            if is_list(values) and Enum.all?(values, &is_binary/1) do
              {:cont, {:ok, Map.put(acc, key, values)}}
            else
              {:halt, {:error, {:invalid_ontology_codes_format, key}}}
            end
          end)

        parsed

      other ->
        {:error, {:invalid_ontology_codes_type, other}}
    end
  end
end
