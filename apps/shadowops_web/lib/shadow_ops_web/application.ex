defmodule ShadowOpsWeb.Application do
  @moduledoc "Application supervisor for the ShadowOps web interface."

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: ShadowOpsWeb.PubSub},
      {ShadowOpsWeb.RateLimit, [clean_period: :timer.minutes(10)]},
      ShadowOpsWeb.RuntimeSnapshotCache,
      ShadowOpsWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ShadowOpsWeb.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ShadowOpsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
