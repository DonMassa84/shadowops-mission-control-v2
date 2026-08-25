defmodule ShadowOpsWeb.NodesController do
  use Phoenix.Controller, formats: [:json]

  alias ShadowOpsCore.{ExecutionService, GovernanceGate, Node}
  alias ShadowOpsWeb.NodeCatalog

  def index(conn, _params) do
    json(conn, NodeCatalog.snapshot())
  end

  def show(conn, %{"id" => id}) do
    case NodeCatalog.get(id) do
      {:ok, node} -> json(conn, node)
      {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "node_not_found"})
    end
  end

  def healthcheck(conn, %{"id" => id} = params), do: governed_action(conn, id, "status", params)
  def start(conn, %{"id" => id} = params), do: governed_action(conn, id, "start", params)
  def stop(conn, %{"id" => id} = params), do: governed_action(conn, id, "stop", params)

  defp governed_action(conn, id, action, params) do
    actor = conn.assigns.actor

    case NodeCatalog.get(id) do
      {:ok, node} ->
        if Node.logical?(node) do
          logical_action(conn, node, id, action, actor)
        else
          physical_action(conn, id, action, actor, params)
        end

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "node_not_found"})
    end
  end

  defp logical_action(conn, node, id, action, actor) do
    capability = "node.#{action}"
    input = %{node_id: id, action: action}
    context = %{request_id: List.first(get_resp_header(conn, "x-request-id"))}

    with true <- Node.action_allowed?(node, action),
         {:ok, _decision} <- GovernanceGate.authorize(capability, actor, id, input, context) do
      action_result(conn, NodeCatalog.execute_action(id, action, actor))
    else
      false -> action_result(conn, {:error, :action_not_allowed})
      {:error, reason} -> governance_error(conn, reason)
    end
  end

  defp physical_action(conn, id, action, actor, params) do
    capability = "node.#{action}"
    input = %{node_id: id, action: action}

    context = %{
      request_id: List.first(get_resp_header(conn, "x-request-id")),
      approval_id: params["approval_id"]
    }

    case ExecutionService.execute(capability, actor, id, input, context) do
      {:ok, result} -> json(conn, result)
      {:error, reason} -> governance_error(conn, reason)
    end
  end

  defp action_result(conn, {:ok, result}), do: json(conn, result)

  defp action_result(conn, {:error, :action_not_allowed}),
    do: conn |> put_status(:method_not_allowed) |> json(%{error: "action_not_allowed"})

  defp action_result(conn, {:error, reason}),
    do:
      conn
      |> put_status(:service_unavailable)
      |> json(%{error: "action_unavailable", reason: inspect(reason)})

  defp governance_error(conn, :approval_required),
    do: conn |> put_status(:conflict) |> json(%{error: "approval_required"})

  defp governance_error(conn, {:approval_required, _}),
    do: conn |> put_status(:conflict) |> json(%{error: "approval_required"})

  defp governance_error(conn, {:approval_blocked, reason}),
    do: conn |> put_status(:forbidden) |> json(%{error: "approval_blocked", reason: inspect(reason)})

  defp governance_error(conn, {:approval_invalid, reason}),
    do: conn |> put_status(:forbidden) |> json(%{error: "approval_invalid", reason: inspect(reason)})

  defp governance_error(conn, :action_not_allowed),
    do: conn |> put_status(:method_not_allowed) |> json(%{error: "action_not_allowed"})

  defp governance_error(conn, reason),
    do:
      conn
      |> put_status(:service_unavailable)
      |> json(%{error: "action_unavailable", reason: inspect(reason)})
end
