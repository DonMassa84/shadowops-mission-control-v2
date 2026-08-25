defmodule ShadowOpsCore.Workers.WorkflowRunWorker do
  @moduledoc """
  Oban worker for persistent canonical workflow runs.

  Every execution re-enters ShadowOpsCore.ExecutionService so queued work cannot bypass current
  governance, approval or privacy policy. RunStore remains the canonical user-facing lifecycle
  record while Oban provides durable scheduling, retry and recovery.
  """

  use Oban.Worker, queue: :workflows, max_attempts: 3

  alias ShadowOpsCore.{ExecutionService, RunStore}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts}) do
    run_id = args["run_id"]
    workflow_id = args["workflow_id"]
    actor = args["actor"]
    input = Map.put(args["input"] || %{}, "workflow_id", workflow_id)

    context = %{
      approval_id: args["approval_id"],
      resource: workflow_id,
      source: :oban
    }

    with {:ok, _run} <- ensure_running(run_id, actor) do
      case ExecutionService.execute("workflow.execute", actor, workflow_id, input, context) do
        {:ok, result} ->
          _ = RunStore.succeed(run_id, actor, result_summary(result), result_exit_code(result))
          :ok

        {:error, reason} ->
          if attempt >= max_attempts do
            _ = RunStore.fail(run_id, actor, safe_reason(reason), 1)
          end

          {:error, safe_reason(reason)}
      end
    end
  end

  defp ensure_running(run_id, actor) do
    case RunStore.get(run_id) do
      {:ok, %{status: "QUEUED"}} -> RunStore.start(run_id, actor)
      {:ok, %{status: "RUNNING"} = run} -> {:ok, run}
      {:ok, %{status: status}} -> {:error, {:run_not_executable, status}}
      error -> error
    end
  end

  defp result_summary(%{summary: summary}) when is_binary(summary), do: summary
  defp result_summary(%{"summary" => summary}) when is_binary(summary), do: summary
  defp result_summary(_), do: "governed workflow completed"

  defp result_exit_code(%{exit_code: code}) when is_integer(code), do: code
  defp result_exit_code(%{"exit_code" => code}) when is_integer(code), do: code
  defp result_exit_code(_), do: 0

  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason({tag, _detail}) when is_atom(tag), do: Atom.to_string(tag)
  defp safe_reason(_), do: "workflow_execution_failed"
end
