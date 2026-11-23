defmodule MedlumLlm.Datasets.CVLTraining do
  @moduledoc """
  Manages versioned training data for CVL (Clinical Verification Layer) agents.

  The CVL system consists of 5 specialized agents for medical content verification:
  - `:medication` - Validates medication references (drugs, doses, frequencies)
  - `:lab` - Validates lab values and reference ranges
  - `:ontology` - Verifies SNOMED-CT, ICD-10, RxNorm, LOINC codes
  - `:temporal` - Checks temporal consistency in clinical narratives
  - `:differential` - Validates differential diagnosis reasoning

  This module provides:
  - Versioned training data management per agent
  - Stratified splitting by verdict type
  - Lineage tracking from evaluation failures to training data
  - Training data creation from evaluation errors

  ## Training Data Format

  CVL training data follows the NLI (Natural Language Inference) format:

      %{
        id: "sample_001",
        premise: "The patient is on metformin 500mg BID for diabetes.",
        hypothesis: "The patient takes metformin 1000mg daily.",
        verdict: :contradiction,  # :entailment | :contradiction | :neutral
        evidence: ["Dose mismatch: 500mg BID vs 1000mg daily"],
        ontology_codes: ["861004"],  # RxNorm codes
        agent_type: :medication,
        confidence: 0.95
      }

  ## Version Naming

  Training data versions follow the pattern:
  `cvl_{agent}_{version}_{hash_prefix}`

  For example: `cvl_medication_v1.0.0_a1b2c3`

  ## Examples

      # Create training data for medication agent
      {:ok, dataset} = CVLTraining.create(:medication, "v1.0.0",
        positive_samples: entailment_samples,
        negative_samples: contradiction_samples,
        neutral_samples: neutral_samples,
        ontology_sources: ["RxNorm_2026AA"]
      )

      # Load latest training data
      {:ok, dataset} = CVLTraining.load_latest(:medication)

      # Create from evaluation failures
      {:ok, dataset} = CVLTraining.from_eval_failures(:medication, failures, "v1.1.0")
  """

  alias DatasetsEx.{Dataset, Lineage, Splitter, Versioning}

  @cvl_agents [:medication, :lab, :ontology, :temporal, :differential]
  @verdicts [:entailment, :contradiction, :neutral]

  @type agent_type :: :medication | :lab | :ontology | :temporal | :differential
  @type verdict :: :entailment | :contradiction | :neutral

  @type cvl_sample :: %{
          id: String.t(),
          premise: String.t(),
          hypothesis: String.t(),
          verdict: verdict(),
          evidence: [String.t()],
          ontology_codes: [String.t()],
          agent_type: agent_type(),
          confidence: float()
        }

  @doc """
  Create versioned training data for a CVL agent.

  ## Options
    - `:positive_samples` - Entailment samples (required)
    - `:negative_samples` - Contradiction samples (required)
    - `:neutral_samples` - Neutral samples (optional)
    - `:ontology_sources` - List of ontology versions used
    - `:parent_version` - Previous version this derives from
    - `:eval_run_id` - Evaluation run that generated failures

  ## Examples

      {:ok, dataset} = CVLTraining.create(:medication, "v1.0.0",
        positive_samples: positives,
        negative_samples: negatives,
        ontology_sources: ["RxNorm_2026AA", "SNOMED_CT_2026"]
      )
  """
  @spec create(agent_type(), String.t(), keyword()) :: {:ok, Dataset.t()} | {:error, term()}
  def create(agent, version, opts) when agent in @cvl_agents and is_binary(version) do
    positive_samples = Keyword.get(opts, :positive_samples, [])
    negative_samples = Keyword.get(opts, :negative_samples, [])
    neutral_samples = Keyword.get(opts, :neutral_samples, [])
    ontology_sources = Keyword.get(opts, :ontology_sources, [])
    parent_version = Keyword.get(opts, :parent_version)
    eval_run_id = Keyword.get(opts, :eval_run_id)

    # Combine and tag all samples
    all_samples =
      []
      |> Enum.concat(tag_samples(positive_samples, :entailment, agent))
      |> Enum.concat(tag_samples(negative_samples, :contradiction, agent))
      |> Enum.concat(tag_samples(neutral_samples, :neutral, agent))
      |> Enum.with_index()
      |> Enum.map(fn {sample, idx} ->
        Map.put_new(sample, :id, "#{agent}_#{version}_#{idx}")
      end)

    if Enum.empty?(all_samples) do
      {:error, :no_samples_provided}
    else
      dataset_name = cvl_dataset_name(agent, version)

      metadata = %{
        domain: :medical,
        clinical_area: "cvl_training",
        task: :cvl,
        data_license: "internal",
        phi_status: :none,
        access_level: :private,
        agent_type: agent,
        version: version,
        parent_version: parent_version,
        eval_run_id: eval_run_id,
        ontology_sources: ontology_sources,
        sample_counts: %{
          entailment: count_by_verdict(all_samples, :entailment),
          contradiction: count_by_verdict(all_samples, :contradiction),
          neutral: count_by_verdict(all_samples, :neutral)
        },
        created_at: DateTime.utc_now()
      }

      dataset =
        Dataset.new(dataset_name,
          data: all_samples,
          schema: :medical_cvl,
          metadata: metadata,
          artifact_id: Ecto.UUID.generate()
        )

      # Save as versioned dataset
      Versioning.create(dataset, version)
    end
  end

  @doc """
  Load specific version of CVL training data for an agent.

  ## Examples

      {:ok, dataset} = CVLTraining.load(:medication, "v1.0.0")
  """
  @spec load(agent_type(), String.t()) :: {:ok, Dataset.t()} | {:error, term()}
  def load(agent, version) when agent in @cvl_agents and is_binary(version) do
    dataset_name = cvl_dataset_name(agent, version)
    Versioning.load(dataset_name, version)
  end

  @doc """
  Load the latest version of CVL training data for an agent.

  ## Examples

      {:ok, dataset} = CVLTraining.load_latest(:medication)
  """
  @spec load_latest(agent_type()) :: {:ok, Dataset.t()} | {:error, term()}
  def load_latest(agent) when agent in @cvl_agents do
    # Get all versions for this agent and find the latest
    case list_versions(agent) do
      [] ->
        {:error, :no_versions_found}

      versions ->
        latest_version = List.first(versions)
        load(agent, latest_version)
    end
  end

  @doc """
  List all versions for a CVL agent's training data.

  ## Examples

      CVLTraining.list_versions(:medication)
      # => ["v2.0.0", "v1.1.0", "v1.0.0"]
  """
  @spec list_versions(agent_type()) :: [String.t()]
  def list_versions(agent) when agent in @cvl_agents do
    # Search for all datasets matching the agent pattern
    base_name = "cvl_#{agent}"

    base_name
    |> Versioning.list_versions()
    |> Enum.sort(:desc)
  end

  @doc """
  Get version lineage for a CVL agent's training data.

  ## Examples

      CVLTraining.lineage(:medication)
      # => [%{version: "v2.0.0", ...}, %{version: "v1.0.0", ...}]
  """
  @spec lineage(agent_type()) :: [map()]
  def lineage(agent) when agent in @cvl_agents do
    base_name = "cvl_#{agent}"
    Versioning.lineage(base_name)
  end

  @doc """
  Split CVL training data with stratification by verdict.

  Maintains the distribution of entailment/contradiction/neutral
  samples across train and test splits.

  ## Options
    - `:ratio` - Train ratio (default: 0.8)
    - `:seed` - Random seed for reproducibility

  ## Examples

      {:ok, dataset} = CVLTraining.load_latest(:medication)
      {train, test} = CVLTraining.split(dataset, ratio: 0.8, seed: 42)
  """
  @spec split(Dataset.t(), keyword()) :: {Dataset.t(), Dataset.t()}
  def split(%Dataset{} = dataset, opts \\ []) do
    Splitter.stratified_split(dataset, Keyword.put(opts, :label_key, :verdict))
  end

  @doc """
  Create CVL training data from evaluation failures.

  Takes evaluation failures and converts them to CVL training samples,
  creating lineage edges from the evaluation run to the training data.

  ## Parameters
    - `agent` - CVL agent type
    - `failures` - List of evaluation failure maps
    - `version` - Version string for the new training data

  ## Options
    - `:eval_run_id` - ID of the evaluation run
    - `:model` - Model name that produced the failures
    - `:transform_fn` - Custom function to transform failures to samples

  ## Failure Format

  Expected failure format:

      %{
        question: "...",
        predicted: "...",
        expected: "...",
        model_confidence: 0.75,
        error_type: :medication_error | :lab_error | :ontology_error | ...
      }

  ## Examples

      failures = [
        %{question: "...", predicted: "...", expected: "...", error_type: :medication_error}
      ]

      {:ok, dataset} = CVLTraining.from_eval_failures(:medication, failures, "v1.1.0",
        eval_run_id: "eval_001",
        model: "openbio_8b"
      )
  """
  @spec from_eval_failures(agent_type(), [map()], String.t(), keyword()) ::
          {:ok, Dataset.t()} | {:error, term()}
  def from_eval_failures(agent, failures, version, opts \\ [])
      when agent in @cvl_agents and is_list(failures) and is_binary(version) do
    eval_run_id = Keyword.get(opts, :eval_run_id)
    _model = Keyword.get(opts, :model)
    transform_fn = Keyword.get(opts, :transform_fn, &default_failure_transform/2)

    # Transform failures to CVL samples
    samples =
      failures
      |> Enum.filter(&failure_matches_agent?(&1, agent))
      |> Enum.map(&transform_fn.(&1, agent))
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(samples) do
      {:error, :no_matching_failures}
    else
      # Split into positive/negative based on whether model was wrong
      {contradiction_samples, entailment_samples} =
        Enum.split_with(samples, fn s -> s.verdict == :contradiction end)

      create(agent, version,
        positive_samples: entailment_samples,
        negative_samples: contradiction_samples,
        eval_run_id: eval_run_id,
        ontology_sources: Keyword.get(opts, :ontology_sources, [])
      )
    end
  end

  @doc """
  Build an artifact reference for CVL training data.

  Used for lineage tracking between evaluation runs and training data.

  ## Examples

      {:ok, dataset} = CVLTraining.load_latest(:medication)
      ref = CVLTraining.artifact_ref(dataset)
  """
  @spec artifact_ref(Dataset.t(), keyword()) :: LineageIR.ArtifactRef.t()
  def artifact_ref(%Dataset{} = dataset, opts \\ []) do
    Lineage.artifact_ref(dataset,
      Keyword.merge(opts, type: "cvl_training_data")
    )
  end

  @doc """
  Create a lineage edge from an evaluation run to CVL training data.

  ## Examples

      eval_ref = %LineageIR.ArtifactRef{artifact_id: "eval_001", type: "eval_run"}
      training_ref = CVLTraining.artifact_ref(training_dataset)

      edge = CVLTraining.lineage_edge(eval_ref, training_ref,
        relationship: "exported_from",
        metadata: %{agent: :medication}
      )
  """
  @spec lineage_edge(LineageIR.ArtifactRef.t(), LineageIR.ArtifactRef.t(), keyword()) ::
          LineageIR.ProvenanceEdge.t()
  def lineage_edge(source_ref, target_ref, opts \\ []) do
    Lineage.edge(source_ref, target_ref,
      Keyword.put_new(opts, :relationship, "derived_from")
    )
  end

  @doc """
  Get all available CVL agent types.

  ## Examples

      CVLTraining.agent_types()
      # => [:medication, :lab, :ontology, :temporal, :differential]
  """
  @spec agent_types() :: [agent_type()]
  def agent_types, do: @cvl_agents

  @doc """
  Get all valid verdict types.

  ## Examples

      CVLTraining.verdict_types()
      # => [:entailment, :contradiction, :neutral]
  """
  @spec verdict_types() :: [verdict()]
  def verdict_types, do: @verdicts

  @doc """
  Validate that a sample has valid CVL format.

  ## Examples

      sample = %{premise: "...", hypothesis: "...", verdict: :entailment}
      {:ok, _} = CVLTraining.validate_sample(sample)
  """
  @spec validate_sample(map()) :: {:ok, map()} | {:error, [String.t()]}
  def validate_sample(sample) when is_map(sample) do
    errors =
      []
      |> validate_required_cvl_fields(sample)
      |> validate_verdict(sample)
      |> validate_premise_hypothesis(sample)

    if Enum.empty?(errors) do
      {:ok, sample}
    else
      {:error, errors}
    end
  end

  # Private functions

  defp cvl_dataset_name(agent, version) do
    hash_prefix =
      :crypto.hash(:sha256, "#{agent}_#{version}_#{DateTime.utc_now()}")
      |> Base.encode16(case: :lower)
      |> String.slice(0..5)

    "cvl_#{agent}_#{version}_#{hash_prefix}"
  end

  defp tag_samples(samples, verdict, agent) do
    Enum.map(samples, fn sample ->
      sample
      |> Map.put_new(:verdict, verdict)
      |> Map.put_new(:agent_type, agent)
      |> Map.put_new(:evidence, [])
      |> Map.put_new(:ontology_codes, [])
      |> Map.put_new(:confidence, 1.0)
    end)
  end

  defp count_by_verdict(samples, verdict) do
    Enum.count(samples, fn s -> Map.get(s, :verdict) == verdict end)
  end

  defp failure_matches_agent?(failure, agent) do
    error_type = Map.get(failure, :error_type)

    case agent do
      :medication -> error_type in [:medication_error, :drug_error, :dose_error]
      :lab -> error_type in [:lab_error, :lab_value_error, :reference_range_error]
      :ontology -> error_type in [:ontology_error, :code_error, :terminology_error]
      :temporal -> error_type in [:temporal_error, :timeline_error, :date_error]
      :differential -> error_type in [:differential_error, :diagnosis_error, :reasoning_error]
    end
  end

  defp default_failure_transform(failure, agent) do
    %{
      id: Map.get(failure, :id, Ecto.UUID.generate()),
      premise: Map.get(failure, :expected, ""),
      hypothesis: Map.get(failure, :predicted, ""),
      verdict: :contradiction,
      evidence: [Map.get(failure, :error_message, "Prediction mismatch")],
      ontology_codes: Map.get(failure, :ontology_codes, []),
      agent_type: agent,
      confidence: 1.0 - Map.get(failure, :model_confidence, 0.5),
      source: %{
        question: Map.get(failure, :question),
        model: Map.get(failure, :model),
        eval_run_id: Map.get(failure, :eval_run_id)
      }
    }
  end

  defp validate_required_cvl_fields(errors, sample) do
    required = [:premise, :hypothesis, :verdict]
    missing = Enum.reject(required, &Map.has_key?(sample, &1))

    if Enum.empty?(missing) do
      errors
    else
      ["Missing required fields: #{inspect(missing)}" | errors]
    end
  end

  defp validate_verdict(errors, sample) do
    case Map.get(sample, :verdict) do
      verdict when verdict in @verdicts -> errors
      nil -> errors
      other -> ["Invalid verdict: #{inspect(other)}, expected one of #{inspect(@verdicts)}" | errors]
    end
  end

  defp validate_premise_hypothesis(errors, sample) do
    premise = Map.get(sample, :premise)
    hypothesis = Map.get(sample, :hypothesis)

    cond do
      not is_binary(premise) or String.trim(premise) == "" ->
        ["premise must be a non-empty string" | errors]

      not is_binary(hypothesis) or String.trim(hypothesis) == "" ->
        ["hypothesis must be a non-empty string" | errors]

      true ->
        errors
    end
  end
end
