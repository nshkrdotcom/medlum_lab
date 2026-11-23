defmodule MedlumLlm.CVL.SourceIndex do
  @moduledoc """
  Precomputes entities from source documents for CVL verification.

  The SourceIndex extracts medications, labs, diagnoses, and findings from source documents
  using ClinicalNerEx (when available) to enable source-grounded verification by CVL agents.

  ## Purpose

  Instead of each agent re-parsing source documents, the index is built once and passed
  to all agents via `context.source_index`. This improves performance and ensures
  consistent entity extraction across agents.

  ## Structure

  The index contains:

      %{
        medications: [%{text: "metformin 500mg", doc_id: "doc-1", snippet: "...", attributes: %{}}],
        labs: [%{text: "HbA1c 7.2%", doc_id: "doc-1", snippet: "...", attributes: %{}}],
        diagnoses: [%{text: "type 2 diabetes", doc_id: "doc-1", snippet: "...", attributes: %{}}],
        findings: [%{text: "chest pain", doc_id: "doc-1", snippet: "...", attributes: %{}}]
      }

  ## Integration

  - Uses `ClinicalNerEx` when available for high-quality entity extraction.
  - Falls back to empty lists when unavailable (agents will degrade to `:neutral`).
  - Preserves `doc_id` and evidence snippets for agent evidence reporting.

  ## Examples

      iex> documents = [
      ...>   %{id: "doc-1", text: "Patient on metformin 500mg for diabetes. HbA1c 7.2%."},
      ...>   %{id: "doc-2", text: "Lab results: creatinine 1.2 mg/dL."}
      ...> ]
      iex> {:ok, index} = SourceIndex.build(documents)
      iex> length(index.medications) > 0
      true

  """

  @type entity :: %{
          text: String.t(),
          doc_id: String.t() | nil,
          snippet: String.t(),
          attributes: map()
        }

  @type index :: %{
          medications: [entity()],
          labs: [entity()],
          diagnoses: [entity()],
          findings: [entity()]
        }

  @doc """
  Build a source index from a list of documents.

  ## Arguments

  - `documents` - List of documents, can be:
    - Plain strings
    - Maps with `:id` and `:text` keys
    - Maps with string keys `"id"` and `"text"`

  ## Options

  - `:method` - Extraction method for ClinicalNerEx (default: `:hybrid`)
  - `:confidence_threshold` - Minimum confidence for entities (default: 0.5)
  - `:snippet_context` - Characters of context around entities (default: 100)

  ## Returns

  `{:ok, index}` where index contains `:medications`, `:labs`, `:diagnoses`, `:findings`.

  ## Examples

      iex> SourceIndex.build(["Patient on lisinopril 10mg"])
      {:ok, %{medications: [...], labs: [], diagnoses: [], findings: []}}

  """
  @spec build([String.t() | map()], keyword()) :: {:ok, index()} | {:error, term()}
  def build(documents, opts \\ []) do
    documents = normalize_documents(documents)

    if clinical_ner_available?() do
      build_with_ner(documents, opts)
    else
      # ClinicalNerEx not available - return empty index
      # Agents should degrade to :neutral when source evidence is unavailable
      {:ok, empty_index()}
    end
  end

  @doc """
  Build a source index, raising on error.

  ## Examples

      iex> index = SourceIndex.build!(["Patient on metformin"])
      iex> is_map(index)
      true

  """
  @spec build!([String.t() | map()], keyword()) :: index()
  def build!(documents, opts \\ []) do
    {:ok, index} = build(documents, opts)
    index
  end

  @doc """
  Returns an empty index structure.

  Useful for testing or when source documents are not available.

  ## Examples

      iex> SourceIndex.empty_index()
      %{medications: [], labs: [], diagnoses: [], findings: []}

  """
  @spec empty_index() :: index()
  def empty_index do
    %{
      medications: [],
      labs: [],
      diagnoses: [],
      findings: []
    }
  end

  @doc """
  Check if ClinicalNerEx is available.

  ## Examples

      iex> is_boolean(SourceIndex.clinical_ner_available?())
      true

  """
  @spec clinical_ner_available?() :: boolean()
  def clinical_ner_available? do
    Code.ensure_loaded?(ClinicalNerEx)
  end

  # Normalize documents to a consistent format
  defp normalize_documents(documents) do
    documents
    |> Enum.with_index()
    |> Enum.map(fn {doc, index} ->
      case doc do
        doc when is_binary(doc) ->
          %{id: "doc-#{index + 1}", text: doc}

        %{id: id, text: text} ->
          %{id: to_string(id), text: text}

        %{"id" => id, "text" => text} ->
          %{id: to_string(id), text: text}

        doc when is_map(doc) ->
          id = doc[:id] || doc["id"] || "doc-#{index + 1}"
          text = doc[:text] || doc["text"] || doc[:content] || doc["content"] || ""
          %{id: to_string(id), text: text}

        _ ->
          %{id: "doc-#{index + 1}", text: ""}
      end
    end)
    |> Enum.reject(fn doc -> doc.text == "" end)
  end

  # Build index using ClinicalNerEx
  defp build_with_ner(documents, opts) do
    snippet_context = Keyword.get(opts, :snippet_context, 100)
    ner_opts = Keyword.take(opts, [:method, :confidence_threshold])

    # Extract entities from each document
    results =
      Enum.flat_map(documents, fn doc ->
        case extract_entities(doc.text, ner_opts) do
          {:ok, entities} ->
            Enum.map(entities, fn entity ->
              Map.merge(entity, %{
                doc_id: doc.id,
                snippet: extract_snippet(doc.text, entity, snippet_context)
              })
            end)

          {:error, _} ->
            []
        end
      end)

    # Group by entity type
    index = %{
      medications: filter_by_type(results, [:medication]),
      labs: filter_by_type(results, [:lab_value, :lab]),
      diagnoses: filter_by_type(results, [:diagnosis, :condition]),
      findings: filter_by_type(results, [:finding, :symptom])
    }

    {:ok, index}
  end

  # Extract entities using ClinicalNerEx
  defp extract_entities(text, opts) do
    apply(ClinicalNerEx, :extract, [text, opts])
  end

  # Filter entities by type
  defp filter_by_type(entities, types) do
    Enum.filter(entities, fn entity ->
      entity_type = entity[:type] || entity["type"]
      entity_type in types
    end)
    |> Enum.map(&normalize_entity/1)
  end

  # Normalize entity to consistent format
  defp normalize_entity(entity) do
    %{
      text: entity[:text] || entity["text"] || "",
      doc_id: entity[:doc_id] || entity["doc_id"],
      snippet: entity[:snippet] || entity["snippet"] || "",
      attributes: extract_attributes(entity)
    }
  end

  # Extract relevant attributes from entity
  defp extract_attributes(entity) do
    # Keep any attributes that aren't the standard keys
    standard_keys = [:text, :type, :doc_id, :snippet, :offset, :length, "text", "type", "doc_id", "snippet", "offset", "length"]

    entity
    |> Enum.reject(fn {k, _v} -> k in standard_keys end)
    |> Map.new()
  end

  # Extract a snippet of context around an entity
  defp extract_snippet(text, entity, context_chars) do
    offset = entity[:offset] || entity["offset"] || 0
    length = entity[:length] || entity["length"] || String.length(entity[:text] || entity["text"] || "")

    start_pos = max(0, offset - context_chars)
    end_pos = min(String.length(text), offset + length + context_chars)

    text
    |> String.slice(start_pos, end_pos - start_pos)
    |> String.trim()
  end
end
