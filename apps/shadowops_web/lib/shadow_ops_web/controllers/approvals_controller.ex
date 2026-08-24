defmodule ShadowOpsWeb.ApprovalsController do
  use Phoenix.Controller, formats: [:json]

  alias ShadowOpsApi

  def index(conn, _params) do
    data = ShadowOpsApi.approvals()
    json(conn, data |> Map.put(:approvals, data.records) |> Map.put(:count, data.record_count))
  end

  def show(conn, %{"id" => id}) do
    case ShadowOpsApi.get_approval(id) do
      {:ok, approval} -> json(conn, approval)
      {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "approval_not_found"})
    end
  end

  def create(conn, params) do
    attrs = Map.put(params, "requested_by", conn.assigns.actor)

    case ShadowOpsApi.create_approval(attrs) do
      {:ok, approval} ->
        conn |> put_status(:created) |> json(approval)

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def approve(conn, %{"id" => id}) do
    actor = get_actor(conn)

    case ShadowOpsApi.approve(id, actor) do
      {:ok, result} ->
        json(conn, result)

      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{error: inspect(reason)})
    end
  end

  def reject(conn, %{"id" => id}) do
    actor = get_actor(conn)

    case ShadowOpsApi.reject(id, actor) do
      {:ok, result} ->
        json(conn, result)

      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{error: inspect(reason)})
    end
  end

  defp get_actor(conn) do
    conn.assigns.actor
  end
end
