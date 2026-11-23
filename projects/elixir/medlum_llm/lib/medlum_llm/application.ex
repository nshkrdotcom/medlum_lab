defmodule MedlumLlm.Application do
  @moduledoc """
  MedlumLlm OTP Application.

  Starts the supervision tree with optional evaluation infrastructure
  based on the `:enable_eval` configuration setting.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = base_children() ++ eval_children()
    Supervisor.start_link(children, strategy: :one_for_one, name: MedlumLlm.Supervisor)
  end

  defp base_children do
    # MedlumLlm is currently stateless - no base children needed
    []
  end

  defp eval_children do
    if Application.get_env(:medlum_llm, :enable_eval, false) do
      [
        {Task.Supervisor, name: MedlumLlm.Eval.TaskSupervisor}
      ]
    else
      []
    end
  end
end
