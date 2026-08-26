defmodule ShadowOpsWeb.HighValueWorkflowsController do
  use Phoenix.Controller, formats: [:json]

  alias ShadowOpsWeb.HighValueWorkflows

  def index(conn, _params), do: json(conn, HighValueWorkflows.all())

  def show(conn, %{"workflow" => workflow}) do
    case HighValueWorkflows.snapshot(workflow) do
      {:ok, result} ->
        json(conn, result)

      {:error, :unknown_high_value_workflow} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "unknown_high_value_workflow"})
    end
  end
end
