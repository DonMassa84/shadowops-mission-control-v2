defmodule ShadowOpsCore.WorkflowJobs do
  @moduledoc """
  Persistence boundary for governed workflow execution through Oban.

  The API layer performs the normal workflow/approval checks before enqueueing, while the worker
  re-enters ExecutionService at execution time so policy, approval and privacy are validated again.
  Raw prompt/message/secret payloads are deliberately not accepted for persistent job arguments.
  """

  alias ShadowOpsCore.{RunStore, WorkflowRun}
  alias ShadowOpsCore.Workers.WorkflowRunWorker

  @sensitive_keys ~w(prompt task message body content token secret password authorization cookie)

  def enabled?, do: Application.get_env(:shadowops_core, :start_persistence, false) == true

  def enqueue(%WorkflowRun{} = run, actor, input, context \\ %{})
      when is_binary(actor) and is_map(input) and is_map(context) do
    cond do
      not enabled?() ->
        {:error, :persistence_not_configured}

      not persistable?(input) ->
        {:error, :persistent_payload_not_allowed}

      true ->
        args = %{
          "run_id" => run.id,
          "workflow_id" => run.workflow_id,
          "actor" => actor,
          "input" => input,
          "approval_id" => context[:approval_id] || context["approval_id"]
        }

        case args |> WorkflowRunWorker.new(queue: :workflows) |> Oban.insert() do
          {:ok, job} ->
            {:ok, run, %{job_id: job.id, queue: to_string(job.queue)}}

          {:error, reason} ->
            _ = RunStore.block(run.id, actor, "persistent enqueue failed")
            {:error, {:oban_enqueue_failed, safe_reason(reason)}}
        end
    end
  end

  @doc false
  def persistable?(value), do: persistable_value?(value)

  defp persistable_value?(map) when is_map(map) do
    Enum.all?(map, fn {key, value} ->
      normalized = key |> to_string() |> String.downcase()
      normalized not in @sensitive_keys and persistable_value?(value)
    end)
  end

  defp persistable_value?(list) when is_list(list), do: Enum.all?(list, &persistable_value?/1)
  defp persistable_value?(value) when is_binary(value), do: byte_size(value) <= 16_384
  defp persistable_value?(value) when is_number(value) or is_boolean(value) or is_nil(value), do: true
  defp persistable_value?(_), do: false

  defp safe_reason(%Ecto.Changeset{}), do: :invalid_job
  defp safe_reason(reason) when is_atom(reason), do: reason
  defp safe_reason(_), do: :enqueue_failed
end
