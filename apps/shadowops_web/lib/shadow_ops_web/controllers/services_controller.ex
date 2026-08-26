defmodule ShadowOpsWeb.ServicesController do
  use Phoenix.Controller, formats: [:json]

  alias ShadowOpsApi

  alias ShadowOpsCore.{
    ExecutionTracker,
    LocalIntegrationCandidates,
    ServiceClassificationProjection
  }

  def index(conn, _params) do
    data = ShadowOpsApi.services()
    runtime_snapshot = data.services
    classified = ServiceClassificationProjection.project(data, runtime_snapshot)

    json(
      conn,
      Map.put(classified, :integration_candidates, LocalIntegrationCandidates.snapshot())
    )
  end

  def show(conn, %{"id" => id}) do
    case ShadowOpsApi.get_service(id) do
      {:ok, service} ->
        json(conn, service)

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "service_not_found"})
    end
  end

  def operate(conn, %{"id" => id, "action" => action} = params) do
    actor = conn.assigns.actor

    context = %{
      request_id: List.first(get_resp_header(conn, "x-request-id")),
      approval_id: params["approval_id"],
      trigger: "api"
    }

    case ExecutionTracker.execute_service(action, actor, id, context) do
      {:ok, service, run} ->
        json(conn, %{service: service, run: run, evaluation: run.evaluation})

      {:error, :approval_required, run} ->
        conn |> put_status(:conflict) |> json(%{error: "approval_required", run: run})

      {:error, {:approval_required, _}, run} ->
        conn |> put_status(:conflict) |> json(%{error: "approval_required", run: run})

      {:error, {:approval_blocked, reason}, run} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "approval_blocked", reason: inspect(reason), run: run})

      {:error, {:approval_invalid, reason}, run} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "approval_invalid", reason: inspect(reason), run: run})

      {:error, {:unknown_capability, _} = reason, run} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "governance_blocked", reason: inspect(reason), run: run})

      {:error, reason, run} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "service_action_unavailable", reason: inspect(reason), run: run})

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "service_action_unavailable", reason: inspect(reason)})
    end
  end
end
