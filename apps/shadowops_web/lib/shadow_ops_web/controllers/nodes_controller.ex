defmodule ShadowOpsWeb.NodesController do
  use Phoenix.Controller, formats: [:json]

  alias ShadowOpsApi
  alias ShadowOpsCore.GovernanceGate

  def index(conn, _params) do
    json(conn, ShadowOpsApi.nodes())
  end

  def show(conn, %{"id" => id}) do
    case ShadowOpsApi.get_node(id) do
      {:ok, node} -> json(conn, node)
      {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "node_not_found"})
    end
  end

  def healthcheck(conn, %{"id" => id}) do
    governed_action(conn, id, "status")
  end

  def start(conn, %{"id" => id}) do
    governed_action(conn, id, "start")
  end

  def stop(conn, %{"id" => id}) do
    governed_action(conn, id, "stop")
  end

  defp governed_action(conn, id, action) do
    actor = get_actor(conn)
    capability = "node.#{action}"
    input = %{node_id: id, action: action}
    context = %{request_id: List.first(get_resp_header(conn, "x-request-id"))}

    with {:ok, _decision} <- GovernanceGate.authorize(capability, actor, id, input, context) do
      action_result(conn, ShadowOpsApi.execute_node_action(id, action, actor, context))
    else
      {:error, reason} -> governance_error(conn, reason)
    end
  end

  defp get_actor(conn), do: conn.assigns.actor

  defp action_result(conn, {:ok, result}), do: json(conn, result)

  defp action_result(conn, {:error, reason}),
    do:
      conn
      |> put_status(:service_unavailable)
      |> json(%{error: "action_unavailable", reason: inspect(reason)})

  defp governance_error(conn, :approval_required),
    do: conn |> put_status(:conflict) |> json(%{error: "approval_required"})

  defp governance_error(conn, reason),
    do:
      conn
      |> put_status(:forbidden)
      |> json(%{error: "governance_blocked", reason: inspect(reason)})
end
