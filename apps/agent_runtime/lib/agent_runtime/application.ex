defmodule AgentRuntime.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: AgentRuntime.AgentSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: AgentRuntime.Supervisor)
  end
end
