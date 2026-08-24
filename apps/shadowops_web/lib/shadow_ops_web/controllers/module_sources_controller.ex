defmodule ShadowOpsWeb.ModuleSourcesController do
  use Phoenix.Controller, formats: [:json]
  alias ShadowOpsApi

  def system(conn, _params), do: json(conn, ShadowOpsApi.system())
  def connectors(conn, _params), do: json(conn, ShadowOpsApi.connectors())
  def whatsapp(conn, _params), do: json(conn, ShadowOpsApi.whatsapp())
  def social(conn, _params), do: json(conn, ShadowOpsApi.social())
  def career(conn, _params), do: json(conn, ShadowOpsApi.career())
  def backups(conn, _params), do: json(conn, ShadowOpsApi.backups())
  def reporting(conn, _params), do: json(conn, ShadowOpsApi.reporting())

  def connector(conn, %{"id" => id}) do
    case ShadowOpsApi.connector(id) do
      {:ok, connector} ->
        json(conn, connector)

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "connector_not_found"})
    end
  end
end
