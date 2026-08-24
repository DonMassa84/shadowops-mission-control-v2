defmodule ShadowOpsCore.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [ShadowOpsCore.EventBus | persistence_children()]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: ShadowOpsCore.Supervisor
    )
  end

  defp persistence_children do
    if Application.get_env(:shadowops_core, :start_persistence, false) do
      [
        ShadowOpsCore.Repo,
        {Oban, Application.fetch_env!(:shadowops_core, Oban)}
      ]
    else
      []
    end
  end
end
