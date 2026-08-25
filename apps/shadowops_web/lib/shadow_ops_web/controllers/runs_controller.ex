defmodule ShadowOpsWeb.RunsController do
  use Phoenix.Controller, formats: [:json]
  alias ShadowOpsApi
  alias ShadowOpsCore.ResultEvaluator

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

  def evaluation(conn, %{"id" => id}) do
    case ShadowOpsApi.get_run(id) do
      {:ok, run} ->
        json(conn, %{
          run_id: id,
          status: run.status,
          evaluation: evaluation_for(run)
        })

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "run_not_found"})
    end
  end

  defp evaluation_for(%{evaluation: evaluation}) when is_map(evaluation), do: evaluation

  defp evaluation_for(%{status: status, exit_code: exit_code}) when status in ["SUCCESS", "FAILED"] do
    ResultEvaluator.workflow(status, exit_code || if(status == "SUCCESS", do: 0, else: 1))
  end

  defp evaluation_for(_),
    do: %{verdict: "NOT_ASSESSED", score: nil, checks: [], summary: "Execution is not finished."}
end
