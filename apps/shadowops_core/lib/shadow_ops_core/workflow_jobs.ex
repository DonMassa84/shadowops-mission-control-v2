defmodule ShadowOpsCore.WorkflowJobs do
  @moduledoc """
  Persistence boundary for governed workflow execution through Oban.

  Requests are validated against the canonical workflow registry and approval store before they
  are queued. The worker re-enters ExecutionService at execution time so current policy, approval
  and privacy rules are validated again. Raw prompt/message/secret payloads are deliberately not
  accepted for persistent job arguments.
  """

  alias ShadowOpsCore.{ApprovalStore, RunStore, WorkflowManifest, WorkflowRun, WorkflowSource}
  alias ShadowOpsCore.Adapters.CanonicalWorkflowAdapter
  alias ShadowOpsCore.Workers.WorkflowRunWorker

  @sensitive_keys ~w(prompt task message body content token secret password authorization cookie)
  @executable_statuses ["active", "VERIFIED_EXECUTABLE"]

  def enabled?, do: Application.get_env(:shadowops_core, :start_persistence, false) == true

  def enqueue_request(workflow_id, actor, input, context \\ %{})
      when is_binary(workflow_id) and is_binary(actor) and is_map(input) and is_map(context) do
    input = Map.drop(input, [:approval_id, "approval_id"])

    with true <- enabled?() || {:error, :persistence_not_configured},
         true <- persistable?(input) || {:error, :persistent_payload_not_allowed},
         {:ok, registry} <- WorkflowSource.load(),
         {:ok, workflow} <- registry_workflow(registry, workflow_id),
         {:ok, manifest} <- WorkflowManifest.from_registry(workflow_id, workflow),
         :ok <- executable_manifest(manifest),
         {:ok, _adapter} <- CanonicalWorkflowAdapter.adapter_for(manifest),
         {:ok, run} <-
           RunStore.queue(workflow_id, actor, %{
             evidence_ref: value(input, :evidence_ref),
             trigger: value(input, :trigger) || "api",
             node: "local-ryzen"
           }) do
      approval_id = context[:approval_id] || context["approval_id"]

      case ApprovalStore.validate(approval_id, "workflow.execute", workflow_id, "L2") do
        {:ok, _approval} ->
          enqueue(run, actor, input, context)

        {:blocked, _reason} ->
          {:ok, blocked} = RunStore.block(run.id, actor, "approval required")
          {:error, {:approval_required, blocked}}

        {:error, _reason} ->
          {:ok, blocked} = RunStore.block(run.id, actor, "approval required")
          {:error, {:approval_required, blocked}}
      end
    else
      {:error, _} = error -> error
      false -> {:error, :invalid_persistent_workflow_request}
    end
  end

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

  defp registry_workflow(%{"workflows" => workflows}, workflow_id) when is_map(workflows) do
    case Map.fetch(workflows, workflow_id) do
      {:ok, workflow} -> {:ok, workflow}
      :error -> {:error, {:unknown_workflow, workflow_id}}
    end
  end

  defp registry_workflow(_, _), do: {:error, :invalid_workflow_registry}

  defp executable_manifest(manifest) do
    status = manifest |> Map.get(:metadata, %{}) |> Map.get(:registry_status)
    if status in @executable_statuses, do: :ok, else: {:error, {:workflow_not_executable, status}}
  end

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

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
