defmodule ShadowOpsWeb.ServicesController do
  use Phoenix.Controller, formats: [:json]

  alias ShadowOpsApi
  alias ShadowOpsCore.ExecutionService

  def index(conn, _params) do
    json(conn, ShadowOpsApi.services())
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
    capability = "service.#{action}"
    input = %{service_id: id, action: action}

    context = %{
      request_id: List.first(get_resp_header(conn, "x-request-id")),
      approval_id: params["approval_id"]
    }

    case ExecutionService.execute(capability, actor, id, input, context) do
      {:ok, service} ->
        json(conn, service)

      {:error, :approval_required} ->
        conn |> put_status(:conflict) |> json(%{error: "approval_required"})

      {:error, {:approval_required, _}} ->
        conn |> put_status(:conflict) |> json(%{error: "approval_required"})

      {:error, {:approval_blocked, reason}} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "approval_blocked", reason: inspect(reason)})

      {:error, {:approval_invalid, reason}} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "approval_invalid", reason: inspect(reason)})

      {:error, {:unknown_capability, _} = reason} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "governance_blocked", reason: inspect(reason)})

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "service_action_unavailable", reason: inspect(reason)})
    end
  end
end
