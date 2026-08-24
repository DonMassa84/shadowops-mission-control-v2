defmodule ShadowOpsWeb.HealthController do
  use Phoenix.Controller, formats: [:json]

  alias WorkflowEngine.Registry

  def show(conn, _params) do
    case Registry.summary() do
      {:ok, summary} ->
        json(conn, %{status: "ok", service: "shadowops_web", registry: summary})

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "degraded", service: "shadowops_web", registry_error: inspect(reason)})
    end
  end
end
