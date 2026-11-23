defmodule MedlumLlm.Labeling.SampleBuilder do
  @moduledoc """
  Builder functions for medical samples.

  Provides factory functions to construct `LabelingIR.Sample` structs with
  properly structured payloads and metadata for CVL training and verification
  workflows.

  ## Sample Types

  - **NLI Samples** - Premise-hypothesis pairs for NLI classification
  - **Clinical Samples** - Multi-document clinical context for verification
  - **Eval Failure Samples** - Converted from evaluation run failures

  ## Example

      alias MedlumLlm.Labeling.{SampleBuilder, ClinicalDocument}

      # Build NLI sample
      sample = SampleBuilder.build_nli_sample(
        "Patient is on metformin 500mg BID...",
        "Patient takes metformin 1000mg daily.",
        tenant_id: "medlum",
        source_run_id: "eval_001"
      )

      # Build clinical sample
      documents = [
        %{
          type: :discharge_summary,
          content: "Patient discharged...",
          date: ~D[2026-01-15],
          provider_type: "cardiology",
          ontology_codes: ClinicalDocument.empty_ontology_codes()
        }
      ]

      sample = SampleBuilder.build_clinical_sample(
        documents,
        "Generated summary text...",
        claims: [%{"text" => "claim", "span" => [0, 5]}]
      )

  """

  alias LabelingIR.Sample
  alias MedlumLlm.Labeling.ClinicalDocument

  @cvl_pipeline_id "medlum_cvl_training_v1"
  @default_tenant "medlum"
  @default_namespace "cvl"

  @doc """
  Builds an NLI sample from a premise-hypothesis pair.

  Creates a `LabelingIR.Sample` with a payload structured for NLI classification.

  ## Options

  - `:tenant_id` - Tenant identifier (default: "medlum")
  - `:namespace` - Namespace for sub-tenant grouping (default: "cvl")
  - `:pipeline_id` - Override pipeline ID (default: "medlum_cvl_training_v1")
  - `:source_run_id` - ID of the evaluation run that produced this sample
  - `:model` - Model identifier that generated the hypothesis
  - `:model_confidence` - Model's confidence in the generation (0.0-1.0)
  - `:artifacts` - List of `LabelingIR.Artifact` structs to attach
  - `:metadata` - Additional metadata to merge

  ## Examples

      iex> sample = MedlumLlm.Labeling.SampleBuilder.build_nli_sample(
      ...>   "Patient has type 2 diabetes.",
      ...>   "Patient is diabetic.",
      ...>   tenant_id: "medlum"
      ...> )
      iex> sample.payload["task_type"]
      "nli"
      iex> sample.payload["premise"]
      "Patient has type 2 diabetes."

  """
  @spec build_nli_sample(String.t(), String.t(), keyword()) :: Sample.t()
  def build_nli_sample(premise, hypothesis, opts \\ []) when is_binary(premise) and is_binary(hypothesis) do
    id = generate_sample_id()
    tenant_id = Keyword.get(opts, :tenant_id, @default_tenant)
    namespace = Keyword.get(opts, :namespace, @default_namespace)
    pipeline_id = Keyword.get(opts, :pipeline_id, @cvl_pipeline_id)
    source_run_id = Keyword.get(opts, :source_run_id)
    model = Keyword.get(opts, :model)
    model_confidence = Keyword.get(opts, :model_confidence)
    artifacts = Keyword.get(opts, :artifacts, [])
    extra_metadata = Keyword.get(opts, :metadata, %{})

    base_metadata =
      %{
        "source" => "eval_failure",
        "source_run_id" => source_run_id,
        "model" => model,
        "model_confidence" => model_confidence
      }
      |> reject_nils()
      |> Map.merge(extra_metadata)

    %Sample{
      id: id,
      tenant_id: tenant_id,
      namespace: namespace,
      pipeline_id: pipeline_id,
      payload: %{
        "task_type" => "nli",
        "premise" => premise,
        "hypothesis" => hypothesis
      },
      artifacts: artifacts,
      metadata: base_metadata,
      lineage_ref: build_lineage(source_run_id, model),
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Builds a clinical sample from multi-document context.

  Creates a `LabelingIR.Sample` with a payload structured for clinical
  verification, including multiple source documents and extracted claims.

  ## Options

  - `:tenant_id` - Tenant identifier (default: "medlum")
  - `:namespace` - Namespace for sub-tenant grouping (default: "cvl")
  - `:pipeline_id` - Override pipeline ID (default: "medlum_cvl_training_v1")
  - `:claims` - List of claim maps with "text" and "span" keys
  - `:lineage_ref` - Custom lineage reference
  - `:artifacts` - List of `LabelingIR.Artifact` structs to attach
  - `:metadata` - Additional metadata to merge

  ## Examples

      iex> documents = [
      ...>   %{
      ...>     type: :discharge_summary,
      ...>     content: "Patient discharged on metformin...",
      ...>     date: ~D[2026-01-15],
      ...>     provider_type: "endocrinology",
      ...>     ontology_codes: %{snomed_ct: [], icd10: ["E11.9"], rxnorm: ["861004"], loinc: []}
      ...>   }
      ...> ]
      iex> sample = MedlumLlm.Labeling.SampleBuilder.build_clinical_sample(
      ...>   documents,
      ...>   "Patient has well-controlled diabetes.",
      ...>   claims: [%{"text" => "well-controlled", "span" => [12, 27]}]
      ...> )
      iex> sample.payload["task_type"]
      "clinical_verification"
      iex> sample.payload["patient_context"]["document_count"]
      1

  """
  @spec build_clinical_sample([ClinicalDocument.t() | map()], String.t(), keyword()) :: Sample.t()
  def build_clinical_sample(documents, generated_summary, opts \\ [])
      when is_list(documents) and is_binary(generated_summary) do
    id = generate_sample_id()
    tenant_id = Keyword.get(opts, :tenant_id, @default_tenant)
    namespace = Keyword.get(opts, :namespace, @default_namespace)
    pipeline_id = Keyword.get(opts, :pipeline_id, @cvl_pipeline_id)
    claims = Keyword.get(opts, :claims, [])
    lineage_ref = Keyword.get(opts, :lineage_ref)
    artifacts = Keyword.get(opts, :artifacts, [])
    extra_metadata = Keyword.get(opts, :metadata, %{})

    serialized_docs = Enum.map(documents, &serialize_document/1)
    ontology_metadata = extract_ontology_codes(documents)
    metadata = Map.merge(ontology_metadata, extra_metadata)

    %Sample{
      id: id,
      tenant_id: tenant_id,
      namespace: namespace,
      pipeline_id: pipeline_id,
      payload: %{
        "task_type" => "clinical_verification",
        "patient_context" => %{
          "documents" => serialized_docs,
          "document_count" => length(documents)
        },
        "generated_summary" => generated_summary,
        "claims" => claims
      },
      artifacts: artifacts,
      metadata: metadata,
      lineage_ref: lineage_ref,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Builds a sample from an evaluation failure.

  Converts evaluation failure data into a CVL training sample. The failure
  map should contain question/context, predicted answer, and optionally
  the correct answer.

  ## Expected failure map keys

  - `"question"` or `"context"` - The premise text
  - `"predicted"` - The model's predicted answer (becomes hypothesis)
  - `"correct"` - The correct answer (stored in metadata)
  - `"task"` - Task type ("mcq", "binary_qa", etc.)
  - `"model"` - Model identifier
  - `"model_confidence"` - Model's confidence score

  ## Options

  - `:tenant_id` - Tenant identifier (default: "medlum")
  - `:namespace` - Namespace for sub-tenant grouping (default: "cvl")
  - `:run_id` - Evaluation run ID

  ## Examples

      iex> failure = %{
      ...>   "question" => "What medication is the patient taking?",
      ...>   "predicted" => "metformin 1000mg",
      ...>   "correct" => "metformin 500mg BID",
      ...>   "task" => "mcq",
      ...>   "model" => "openbio_8b"
      ...> }
      iex> sample = MedlumLlm.Labeling.SampleBuilder.build_from_eval_failure(
      ...>   failure,
      ...>   run_id: "eval_001"
      ...> )
      iex> sample.payload["task_type"]
      "nli"

  """
  @spec build_from_eval_failure(map(), keyword()) :: Sample.t()
  def build_from_eval_failure(failure, opts \\ []) when is_map(failure) do
    premise = failure["question"] || failure["context"] || ""
    hypothesis = format_hypothesis(failure)
    model = failure["model"]
    model_confidence = failure["model_confidence"]
    correct_answer = failure["correct"]
    run_id = Keyword.get(opts, :run_id)

    extra_metadata = %{
      "correct_answer" => correct_answer,
      "failure_task" => failure["task"]
    } |> reject_nils()

    build_nli_sample(premise, hypothesis,
      Keyword.merge(opts, [
        source_run_id: run_id,
        model: model,
        model_confidence: model_confidence,
        metadata: extra_metadata
      ])
    )
  end

  @doc """
  Generates a unique sample ID with the `cvl_` prefix.

  ## Examples

      iex> id = MedlumLlm.Labeling.SampleBuilder.generate_sample_id()
      iex> String.starts_with?(id, "cvl_")
      true
      iex> String.length(id)
      28

  """
  @spec generate_sample_id() :: String.t()
  def generate_sample_id do
    "cvl_" <> (:crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower))
  end

  # Private helpers

  defp serialize_document(%{type: type, content: content} = doc) do
    %{
      "type" => Atom.to_string(type),
      "content" => content,
      "date" => serialize_date(Map.get(doc, :date)),
      "provider_type" => Map.get(doc, :provider_type),
      "ontology_codes" => serialize_codes(Map.get(doc, :ontology_codes, %{}))
    }
  end

  defp serialize_document(doc) when is_map(doc) do
    # Handle already serialized documents (string keys)
    type = doc["type"] || doc[:type]
    content = doc["content"] || doc[:content]

    %{
      "type" => if(is_atom(type), do: Atom.to_string(type), else: type),
      "content" => content,
      "date" => serialize_date(doc["date"] || doc[:date]),
      "provider_type" => doc["provider_type"] || doc[:provider_type],
      "ontology_codes" => serialize_codes(doc["ontology_codes"] || doc[:ontology_codes] || %{})
    }
  end

  defp serialize_date(nil), do: nil
  defp serialize_date(%Date{} = date), do: Date.to_iso8601(date)
  defp serialize_date(date) when is_binary(date), do: date

  defp serialize_codes(codes) when is_map(codes) do
    %{
      "snomed_ct" => get_codes(codes, :snomed_ct),
      "icd10" => get_codes(codes, :icd10),
      "rxnorm" => get_codes(codes, :rxnorm),
      "loinc" => get_codes(codes, :loinc)
    }
  end

  defp serialize_codes(_), do: %{"snomed_ct" => [], "icd10" => [], "rxnorm" => [], "loinc" => []}

  defp get_codes(codes, key) do
    Map.get(codes, key) || Map.get(codes, Atom.to_string(key)) || []
  end

  defp extract_ontology_codes(documents) do
    all_codes =
      documents
      |> Enum.flat_map(fn doc ->
        codes = Map.get(doc, :ontology_codes) || Map.get(doc, "ontology_codes") || %{}
        [
          {:snomed_ct, get_codes(codes, :snomed_ct)},
          {:icd10, get_codes(codes, :icd10)},
          {:rxnorm, get_codes(codes, :rxnorm)},
          {:loinc, get_codes(codes, :loinc)}
        ]
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {k, v} -> {Atom.to_string(k), List.flatten(v) |> Enum.uniq()} end)

    %{"ontology_annotations" => all_codes}
  end

  defp build_lineage(nil, _model), do: nil

  defp build_lineage(run_id, model) do
    %{
      "source_type" => "eval_failure",
      "eval_run_id" => run_id,
      "model" => model,
      "transformation" => "cvl_sample_builder_v1"
    }
    |> reject_nils()
  end

  defp format_hypothesis(failure) do
    case failure["task"] do
      "mcq" ->
        "The correct answer is #{failure["predicted"]}."

      "binary_qa" ->
        case failure["predicted"] do
          "yes" -> "Yes, this is true based on the evidence."
          "no" -> "No, this is false based on the evidence."
          "maybe" -> "It is uncertain based on the evidence."
          other -> "The answer is #{other}."
        end

      _ ->
        failure["predicted"] || ""
    end
  end

  defp reject_nils(map) do
    Map.reject(map, fn {_, v} -> is_nil(v) end)
  end
end
