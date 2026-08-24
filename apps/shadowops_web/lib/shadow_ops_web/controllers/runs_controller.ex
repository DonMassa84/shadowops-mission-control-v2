defmodule ShadowOpsWeb.RunsController do
  use Phoenix.Controller, formats: [:json]
  alias ShadowOpsApi

  def index(conn, _params) do
    data = ShadowOpsApi.runs()
    json(conn, data |> Map.put(:runs, data.records) |> Map.put(:count, data.record_count))
  end

  def show(conn, %{"id" => id}) do
    case ShadowOpsApi.get_run(id) do
      {:ok, run} -> json(conn, run)
      {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "run_not_found"})
    end
  end
end
