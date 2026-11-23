defmodule MedlumLlm.CVL.LabelingQueue do
  @moduledoc """
  CVL labeling queue management for NLI training data collection.

  Manages the Anvil labeling queue for CVL (Clinical Verification Layer)
  training data. Implements multi-labeler redundancy with 3 labels per
  sample to ensure high-quality consensus annotations.

  ## Features

  - **Redundancy Policy**: Each sample receives 3 independent labels
  - **ACL Management**: Registers labelers with appropriate permissions
  - **Clinical Redaction**: Uses aggressive clinical PII redaction mode
  - **Agreement Thresholds**: Requires 0.80 agreement for training data

  ## Queue Configuration

  The default queue (`cvl_nli_training`) is configured with:
  - 3 labels per sample (redundancy policy)
  - 1 hour assignment timeout
  - Clinical PII redaction enabled
  - No same-labeler reassignment

  ## Usage

      # Create the labeling queue
      {:ok, _queue} = MedlumLlm.CVL.LabelingQueue.create_queue()

      # Register labelers
      :ok = MedlumLlm.CVL.LabelingQueue.register_labelers(["labeler1", "labeler2", "labeler3"])

      # Get the queue identifier
      queue_id = MedlumLlm.CVL.LabelingQueue.queue_id()
      # => "cvl_nli_training"

      # Access the queue via Registry
      queue = MedlumLlm.CVL.LabelingQueue.queue_ref()
  """

  alias MedlumLlm.CVL.LabelingSchema

  require Logger

  @queue_id "cvl_nli_training"
  @default_labels_per_sample 3
  @default_assignment_timeout 3600

  @type queue_opts :: [
          labels_per_sample: pos_integer(),
          assignment_timeout: pos_integer(),
          schema_opts: keyword()
        ]

  @type labeler_role :: :labeler | :reviewer | :owner

  @doc """
  Creates the CVL NLI labeling queue.

  The queue is configured with redundancy policy to ensure multiple
  independent labels per sample.

  ## Options

  - `:labels_per_sample` - Number of labels required per sample (default: 3)
  - `:assignment_timeout` - Timeout in seconds before reassignment (default: 3600)
  - `:schema_opts` - Options passed to LabelingSchema.schema/1

  ## Examples

      iex> {:ok, _queue} = MedlumLlm.CVL.LabelingQueue.create_queue()
      iex> {:ok, _queue} = MedlumLlm.CVL.LabelingQueue.create_queue(labels_per_sample: 5)
  """
  @spec create_queue(queue_opts()) :: {:ok, term()} | {:error, term()}
  def create_queue(opts \\ []) do
    schema_opts = Keyword.get(opts, :schema_opts, [])
    schema = LabelingSchema.schema(schema_opts)
    labels_per_sample = Keyword.get(opts, :labels_per_sample, @default_labels_per_sample)
    assignment_timeout = Keyword.get(opts, :assignment_timeout, @default_assignment_timeout)

    Logger.info(
      "Creating CVL labeling queue: #{@queue_id} with #{labels_per_sample} labels/sample"
    )

    Anvil.create_queue(
      queue_id: @queue_id,
      schema: schema,
      policy: :redundancy,
      labels_per_sample: labels_per_sample,
      assignment_timeout: assignment_timeout,
      storage: Anvil.Storage.ETS,
      policy_config: %{
        allow_same_labeler: false,
        labels_per_sample: labels_per_sample
      }
    )
  end

  @doc """
  Returns the queue identifier for the CVL NLI labeling queue.
  """
  @spec queue_id() :: String.t()
  def queue_id, do: @queue_id

  @doc """
  Returns a reference to the queue process via Registry.

  Use this to call Anvil functions that require a queue reference.

  ## Examples

      iex> queue = MedlumLlm.CVL.LabelingQueue.queue_ref()
      iex> Anvil.Queue.get_labels(queue)
  """
  @spec queue_ref() :: {:via, module(), {module(), String.t()}}
  def queue_ref do
    {:via, Registry, {Anvil.Registry, @queue_id}}
  end

  @doc """
  Registers labelers for the CVL queue with ACL permissions.

  Each labeler is added to the queue and granted the specified role.

  ## Roles

  - `:labeler` - Can request assignments and submit labels (default)
  - `:reviewer` - Can view all labels, audit, and export data
  - `:owner` - Can manage queue membership and settings

  ## Examples

      iex> :ok = MedlumLlm.CVL.LabelingQueue.register_labelers(["user1", "user2"])
      iex> :ok = MedlumLlm.CVL.LabelingQueue.register_labelers(["admin1"], :owner)
  """
  @spec register_labelers([String.t()], labeler_role()) :: :ok | {:error, term()}
  def register_labelers(labeler_ids, role \\ :labeler) when is_list(labeler_ids) do
    queue = queue_ref()

    # Add labelers to the queue
    :ok = Anvil.Queue.add_labelers(queue, labeler_ids)

    # Grant ACL permissions to each labeler
    Enum.each(labeler_ids, fn labeler_id ->
      grant_access(labeler_id, role)
    end)

    Logger.info("Registered #{length(labeler_ids)} labelers with role :#{role}")

    :ok
  end

  @doc """
  Grants queue access to a specific labeler.

  ## Examples

      iex> {:ok, _membership} = MedlumLlm.CVL.LabelingQueue.grant_access("user1", :labeler)
  """
  @spec grant_access(String.t(), labeler_role()) :: {:ok, term()} | {:error, term()}
  def grant_access(labeler_id, role \\ :labeler) do
    Anvil.Auth.ACL.grant_access(%{
      queue_id: @queue_id,
      labeler_id: labeler_id,
      role: role,
      tenant_id: tenant_id(),
      granted_by: "system"
    })
  end

  @doc """
  Adds samples to the CVL labeling queue.

  Samples should have the format expected by Anvil:

      %{
        id: "sample_id",
        premise: "Source document text...",
        hypothesis: "Generated claim to verify...",
        metadata: %{...}
      }

  ## Examples

      iex> samples = [%{id: "s1", premise: "...", hypothesis: "..."}]
      iex> :ok = MedlumLlm.CVL.LabelingQueue.add_samples(samples)
  """
  @spec add_samples([map()]) :: :ok | {:error, term()}
  def add_samples(samples) when is_list(samples) do
    queue = queue_ref()
    Anvil.Queue.add_samples(queue, samples)
  end

  @doc """
  Gets the next assignment for a labeler.

  ## Examples

      iex> {:ok, assignment} = MedlumLlm.CVL.LabelingQueue.get_next_assignment("labeler1")
      iex> assignment.sample_id
      "sample_123"
  """
  @spec get_next_assignment(String.t()) ::
          {:ok, Anvil.Assignment.t()} | {:error, term()}
  def get_next_assignment(labeler_id) do
    queue = queue_ref()
    Anvil.Queue.get_next_assignment(queue, labeler_id)
  end

  @doc """
  Submits a label for an assignment.

  The values must conform to the CVL NLI schema (verdict, confidence,
  optionally evidence_quality and reasoning).

  ## Examples

      iex> values = %{
      ...>   "verdict" => "ENTAILMENT",
      ...>   "confidence" => 4,
      ...>   "evidence_quality" => "clear"
      ...> }
      iex> {:ok, label} = MedlumLlm.CVL.LabelingQueue.submit_label("assignment_id", values)
  """
  @spec submit_label(String.t(), map()) :: {:ok, Anvil.Label.t()} | {:error, term()}
  def submit_label(assignment_id, values) do
    queue = queue_ref()
    Anvil.Queue.submit_label(queue, assignment_id, values)
  end

  @doc """
  Gets all labels from the queue.

  ## Options

  - `:sample_id` - Filter by sample ID
  - `:labeler_id` - Filter by labeler ID
  - `:status` - Filter by status (:completed, :pending, etc.)

  ## Examples

      iex> labels = MedlumLlm.CVL.LabelingQueue.get_labels()
      iex> labels = MedlumLlm.CVL.LabelingQueue.get_labels(sample_id: "sample_123")
  """
  @spec get_labels(keyword()) :: [Anvil.Label.t()]
  def get_labels(filters \\ []) do
    queue = queue_ref()
    Anvil.Queue.get_labels(queue, filters)
  end

  @doc """
  Gets all assignments from the queue.

  ## Examples

      iex> assignments = MedlumLlm.CVL.LabelingQueue.get_assignments()
  """
  @spec get_assignments(keyword()) :: [Anvil.Assignment.t()]
  def get_assignments(filters \\ []) do
    queue = queue_ref()
    Anvil.Queue.get_assignments(queue, filters)
  end

  @doc """
  Computes agreement metrics for labels in the queue.

  ## Options

  - `:field` - Field to compute agreement for (default: "verdict")
  - `:metric` - Specific metric to use (:cohen, :fleiss, :krippendorff)

  ## Examples

      iex> {:ok, score} = MedlumLlm.CVL.LabelingQueue.compute_agreement()
      iex> score
      0.85

      iex> {:ok, score} = MedlumLlm.CVL.LabelingQueue.compute_agreement(field: "confidence")
  """
  @spec compute_agreement(keyword()) :: {:ok, float()} | {:error, term()}
  def compute_agreement(opts \\ []) do
    labels = get_labels()
    field = Keyword.get(opts, :field, "verdict")

    Anvil.Agreement.compute_for_field(labels, field, opts)
  end

  @doc """
  Returns queue statistics.

  ## Examples

      iex> stats = MedlumLlm.CVL.LabelingQueue.stats()
      iex> stats.total_samples
      100
  """
  @spec stats() :: map()
  def stats do
    labels = get_labels()
    assignments = get_assignments()

    completed_assignments = Enum.filter(assignments, &(&1.status == :completed))
    unique_samples = assignments |> Enum.map(& &1.sample_id) |> Enum.uniq()

    %{
      total_labels: length(labels),
      total_assignments: length(assignments),
      completed_assignments: length(completed_assignments),
      total_samples: length(unique_samples),
      unique_labelers: labels |> Enum.map(& &1.labeler_id) |> Enum.uniq() |> length()
    }
  end

  # Private helpers

  defp tenant_id do
    Application.get_env(:medlum_llm, :tenant_id, "medlum")
  end
end
