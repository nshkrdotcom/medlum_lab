defmodule MedlumLlm.Integration.VersionCheck do
  @moduledoc """
  Verifies NSAI library versions are compatible.

  This module provides utilities to check that all required NSAI ecosystem
  libraries are loaded and available. It's useful for:

  - Startup validation to ensure all dependencies are present
  - Debugging integration issues
  - CI/CD health checks

  ## Usage

      # Check all NSAI libraries
      case MedlumLlm.Integration.VersionCheck.check_all() do
        :ok -> IO.puts("All NSAI libraries loaded")
        {:error, errors} -> IO.inspect(errors, label: "Missing libraries")
      end

      # Check a specific library
      :ok = MedlumLlm.Integration.VersionCheck.check_library(:eval_ex)

  ## Mix Alias

  You can also run this via mix:

      mix check.nsai

  """

  @required_versions %{
    eval_ex: "~> 0.1.5",
    crucible_bench: "~> 0.4.0",
    crucible_harness: "~> 0.3.3",
    hf_datasets_ex: "~> 0.1.2",
    crucible_ensemble: "~> 0.4.1"
  }

  @doc """
  Check all NSAI libraries are available and compatible.

  Returns `:ok` if all libraries are loaded, or `{:error, errors}` with
  a list of `{library, reason}` tuples for any that failed.

  ## Examples

      iex> MedlumLlm.Integration.VersionCheck.check_all()
      :ok

      iex> MedlumLlm.Integration.VersionCheck.check_all()
      {:error, [{:eval_ex, :not_loaded}]}

  """
  @spec check_all() :: :ok | {:error, [{atom(), term()}]}
  def check_all do
    errors =
      Enum.flat_map(@required_versions, fn {lib, _version} ->
        case check_library(lib) do
          :ok -> []
          {:error, reason} -> [{lib, reason}]
        end
      end)

    if Enum.empty?(errors) do
      :ok
    else
      {:error, errors}
    end
  end

  @doc """
  Check a specific library is loaded.

  ## Examples

      iex> MedlumLlm.Integration.VersionCheck.check_library(:jason)
      :ok

      iex> MedlumLlm.Integration.VersionCheck.check_library(:nonexistent)
      {:error, :not_loaded}

  """
  @spec check_library(atom()) :: :ok | {:error, term()}
  def check_library(lib) do
    module = lib_to_module(lib)

    if Code.ensure_loaded?(module) do
      :ok
    else
      {:error, :not_loaded}
    end
  end

  @doc """
  Get the required version spec for a library.

  ## Examples

      iex> MedlumLlm.Integration.VersionCheck.required_version(:eval_ex)
      "~> 0.1.5"

  """
  @spec required_version(atom()) :: String.t() | nil
  def required_version(lib) do
    Map.get(@required_versions, lib)
  end

  @doc """
  List all required NSAI libraries and their version specs.

  ## Examples

      iex> MedlumLlm.Integration.VersionCheck.required_libraries()
      %{eval_ex: "~> 0.1.5", crucible_bench: "~> 0.4.0", ...}

  """
  @spec required_libraries() :: %{atom() => String.t()}
  def required_libraries, do: @required_versions

  # Maps library atom names to their main module names
  defp lib_to_module(:eval_ex), do: EvalEx
  defp lib_to_module(:crucible_bench), do: CrucibleBench
  defp lib_to_module(:crucible_harness), do: CrucibleHarness
  defp lib_to_module(:hf_datasets_ex), do: HfDatasetsEx
  defp lib_to_module(:crucible_ensemble), do: CrucibleEnsemble
  defp lib_to_module(:metrics_ex), do: MetricsEx
  defp lib_to_module(:datasets_ex), do: DatasetsEx
  defp lib_to_module(:hf_hub_ex), do: HfHubEx
  defp lib_to_module(:embed_ex), do: EmbedEx
  defp lib_to_module(:llm_guard), do: LlmGuard
  defp lib_to_module(:forge), do: Forge
  defp lib_to_module(:anvil), do: Anvil
  defp lib_to_module(:labeling_ir), do: LabelingIR

  # Fallback: convert snake_case to CamelCase
  defp lib_to_module(lib) do
    lib
    |> Atom.to_string()
    |> Macro.camelize()
    |> String.to_atom()
  end
end
