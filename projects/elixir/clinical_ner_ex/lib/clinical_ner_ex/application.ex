defmodule ClinicalNerEx.Application do
  @moduledoc """
  OTP Application for clinical_ner_ex.

  Starts the supervision tree with the following children:

  - `ClinicalNerEx.Cache` - ETS-based cache for patterns, dictionaries, and linking results
  - `Task.Supervisor` - For parallel extraction tasks
  - `DynamicSupervisor` - For ML model serving processes (when transformer models are loaded)

  ## Supervision Tree

      ClinicalNerEx.Application
          |
          +-- ClinicalNerEx.Cache (ETS table owner)
          |
          +-- Task.Supervisor (parallel extraction)
          |
          +-- ClinicalNerEx.Models.Supervisor (DynamicSupervisor)
                  +-- Nx.Serving processes for loaded models
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Cache for patterns and dictionaries
      {ClinicalNerEx.Cache, []},

      # Task supervisor for parallel extraction
      {Task.Supervisor, name: ClinicalNerEx.TaskSupervisor},

      # Model supervisor for ML models (if available)
      {DynamicSupervisor, name: ClinicalNerEx.Models.Supervisor, strategy: :one_for_one}
    ]

    # Attach telemetry handlers
    ClinicalNerEx.Telemetry.setup()

    opts = [strategy: :one_for_one, name: ClinicalNerEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
