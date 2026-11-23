defmodule MedlumLlm.Datasets.Metadata do
  @moduledoc """
  Medical metadata schema for dataset lineage tracking.

  Defines the standard metadata structure for medical datasets,
  ensuring consistent tracking of domain, clinical area, PHI status,
  access levels, and evaluation baselines.

  ## Metadata Schema

  Medical datasets include extended metadata beyond standard datasets:

  - `domain` - Always `:medical` for medical datasets
  - `clinical_area` - Clinical specialization (e.g., "usmle", "icu", "radiology")
  - `task` - Task type (`:mcq`, `:binary_qa`, `:reasoning`, `:ner`, `:cvl`)
  - `data_license` - License string (e.g., "MIT", "Apache-2.0")
  - `phi_status` - PHI handling status (`:none`, `:synthetic`, `:deidentified`, `:phi`)
  - `access_level` - Access restrictions (`:public`, `:gated`, `:private`)
  - `hf_repo` - HuggingFace repository ID
  - `hf_revision` - Pinned revision for reproducibility
  - `hf_split` - Dataset split name
  - `loaded_at` - When the dataset was loaded
  - `baselines` - Map of model name to accuracy baselines

  ## Examples

      config = %{
        clinical_area: "usmle",
        task: :mcq,
        data_license: "MIT",
        phi_status: :none,
        access_level: :public,
        baselines: %{"GPT-4" => 86.1}
      }

      metadata = MedlumLlm.Datasets.Metadata.build(config, %{
        hf_repo: "bigbio/med_qa",
        hf_split: "test",
        loaded_at: DateTime.utc_now()
      })

      {:ok, _} = MedlumLlm.Datasets.Metadata.validate(metadata)
  """

  @type phi_status :: :none | :synthetic | :deidentified | :phi
  @type access_level :: :public | :gated | :private
  @type task_type :: :mcq | :binary_qa | :reasoning | :ner | :cvl

  @type medical_metadata :: %{
          domain: :medical,
          clinical_area: String.t(),
          task: task_type(),
          data_license: String.t(),
          phi_status: phi_status(),
          access_level: access_level(),
          hf_repo: String.t(),
          hf_revision: String.t() | nil,
          hf_split: String.t(),
          loaded_at: DateTime.t(),
          baselines: map() | nil
        }

  @required_fields [:domain, :clinical_area, :task, :phi_status, :access_level]
  @valid_tasks [:mcq, :binary_qa, :reasoning, :ner, :cvl]
  @valid_phi_statuses [:none, :synthetic, :deidentified, :phi]
  @valid_access_levels [:public, :gated, :private]

  @doc """
  Build medical metadata from configuration and load information.

  ## Parameters

    - `config` - Dataset configuration map with fields like `clinical_area`, `task`, etc.
    - `load_info` - Runtime information like `hf_repo`, `hf_split`, `loaded_at`

  ## Examples

      metadata = Metadata.build(
        %{clinical_area: "usmle", task: :mcq, phi_status: :none, access_level: :public},
        %{hf_repo: "bigbio/med_qa", hf_split: "test"}
      )
  """
  @spec build(map(), map()) :: medical_metadata()
  def build(config, load_info) when is_map(config) and is_map(load_info) do
    %{
      domain: :medical,
      clinical_area: to_string(Map.get(config, :clinical_area, "general")),
      task: Map.get(config, :task, :mcq),
      data_license: to_string(Map.get(config, :data_license, "unknown")),
      phi_status: Map.get(config, :phi_status, :none),
      access_level: Map.get(config, :access_level, :public),
      hf_repo: to_string(Map.get(load_info, :hf_repo, "")),
      hf_revision: Map.get(load_info, :hf_revision),
      hf_split: to_string(Map.get(load_info, :hf_split, "")),
      loaded_at: Map.get(load_info, :loaded_at, DateTime.utc_now()),
      baselines: Map.get(config, :baselines),
      sample_count: Map.get(load_info, :sample_count)
    }
  end

  @doc """
  Validate medical metadata for required fields and valid values.

  ## Examples

      {:ok, _} = Metadata.validate(%{domain: :medical, clinical_area: "usmle", ...})
      {:error, errors} = Metadata.validate(%{domain: :medical})
  """
  @spec validate(map()) :: {:ok, map()} | {:error, [String.t()]}
  def validate(metadata) when is_map(metadata) do
    errors =
      []
      |> validate_required_fields(metadata)
      |> validate_domain(metadata)
      |> validate_task(metadata)
      |> validate_phi_status(metadata)
      |> validate_access_level(metadata)
      |> validate_clinical_area(metadata)

    if Enum.empty?(errors) do
      {:ok, metadata}
    else
      {:error, errors}
    end
  end

  @doc """
  Check if metadata indicates PHI presence.

  ## Examples

      Metadata.has_phi?(%{phi_status: :deidentified})  # => false
      Metadata.has_phi?(%{phi_status: :phi})           # => true
  """
  @spec has_phi?(map()) :: boolean()
  def has_phi?(metadata) when is_map(metadata) do
    Map.get(metadata, :phi_status) == :phi
  end

  @doc """
  Check if metadata indicates gated or private access.

  ## Examples

      Metadata.requires_access?(%{access_level: :public})  # => false
      Metadata.requires_access?(%{access_level: :gated})   # => true
  """
  @spec requires_access?(map()) :: boolean()
  def requires_access?(metadata) when is_map(metadata) do
    Map.get(metadata, :access_level) in [:gated, :private]
  end

  @doc """
  Get baseline accuracy for a specific model if available.

  ## Examples

      Metadata.get_baseline(%{baselines: %{"GPT-4" => 86.1}}, "GPT-4")
      # => {:ok, 86.1}

      Metadata.get_baseline(%{baselines: nil}, "GPT-4")
      # => :not_available
  """
  @spec get_baseline(map(), String.t()) :: {:ok, number()} | :not_available
  def get_baseline(metadata, model_name) when is_map(metadata) and is_binary(model_name) do
    case Map.get(metadata, :baselines) do
      nil ->
        :not_available

      baselines when is_map(baselines) ->
        case Map.get(baselines, model_name) do
          nil -> :not_available
          value -> {:ok, value}
        end

      _ ->
        :not_available
    end
  end

  @doc """
  Create a minimal metadata map for testing purposes.

  ## Examples

      metadata = Metadata.minimal()
      # => %{domain: :medical, clinical_area: "test", task: :mcq, ...}
  """
  @spec minimal() :: medical_metadata()
  def minimal do
    %{
      domain: :medical,
      clinical_area: "test",
      task: :mcq,
      data_license: "MIT",
      phi_status: :none,
      access_level: :public,
      hf_repo: "test/dataset",
      hf_revision: nil,
      hf_split: "test",
      loaded_at: DateTime.utc_now(),
      baselines: nil
    }
  end

  @doc """
  Merge additional metadata into existing medical metadata.

  ## Examples

      base = Metadata.minimal()
      extended = Metadata.merge(base, %{custom_field: "value"})
  """
  @spec merge(map(), map()) :: map()
  def merge(base_metadata, additional) when is_map(base_metadata) and is_map(additional) do
    Map.merge(base_metadata, additional)
  end

  # Validation helpers

  defp validate_required_fields(errors, metadata) do
    missing =
      @required_fields
      |> Enum.reject(fn field -> Map.has_key?(metadata, field) end)

    if Enum.empty?(missing) do
      errors
    else
      ["Missing required fields: #{inspect(missing)}" | errors]
    end
  end

  defp validate_domain(errors, metadata) do
    case Map.get(metadata, :domain) do
      :medical -> errors
      nil -> errors
      other -> ["Invalid domain: #{inspect(other)}, expected :medical" | errors]
    end
  end

  defp validate_task(errors, metadata) do
    case Map.get(metadata, :task) do
      task when task in @valid_tasks -> errors
      nil -> errors
      other -> ["Invalid task: #{inspect(other)}, expected one of #{inspect(@valid_tasks)}" | errors]
    end
  end

  defp validate_phi_status(errors, metadata) do
    case Map.get(metadata, :phi_status) do
      status when status in @valid_phi_statuses -> errors
      nil -> errors
      other -> ["Invalid phi_status: #{inspect(other)}, expected one of #{inspect(@valid_phi_statuses)}" | errors]
    end
  end

  defp validate_access_level(errors, metadata) do
    case Map.get(metadata, :access_level) do
      level when level in @valid_access_levels -> errors
      nil -> errors
      other -> ["Invalid access_level: #{inspect(other)}, expected one of #{inspect(@valid_access_levels)}" | errors]
    end
  end

  defp validate_clinical_area(errors, metadata) do
    case Map.get(metadata, :clinical_area) do
      nil -> errors
      area when is_binary(area) and byte_size(area) > 0 -> errors
      "" -> ["clinical_area cannot be empty" | errors]
      other -> ["Invalid clinical_area: #{inspect(other)}, expected non-empty string" | errors]
    end
  end
end
