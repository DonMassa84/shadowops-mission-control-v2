defmodule ShadowOpsCore.ExecutionTracker do
  @moduledoc """
  Records governed workflow and service actions as durable execution runs and evaluates their
  observed result.

  This module never calls runtime adapters directly. Every mutation goes through ExecutionService.
  """

  alias ShadowOpsCore.{
    ApprovalStore,
    ExecutionService,
    ResultEvaluator,
    RunStore,
    RuntimeSources
  }

  @service_actions ["start", "restart", "stop"]

  def execute_workflow(workflow_id, actor, input, context \\ %{})
      when is_binary(workflow_id) and is_binary(actor) and is_map(input) and is_map(context) do
    input = Map.drop(input, [:approval_id, "approval_id"])

    with {:ok, queued} <-
           RunStore.queue(workflow_id, actor, %{
             evidence_ref: value(input, :evidence_ref),
             trigger: value(input, :trigger) || "api",
             node: "local-ryzen"
           }) do
      case authorize_workflow(context, workflow_id) do
        :ok -> execute_approved_workflow(queued, workflow_id, actor, input, context)
        {:error, reason} -> block_workflow(queued, actor, reason)
      end
    end
  end

  def execute_workflow(_workflow_id, _actor, _input, _context),
    do: {:error, :invalid_workflow_execution_request}

  def execute_service(action, actor, service_id, context \\ %{})

  def execute_service(action, actor, service_id, context)
      when action in @service_actions and is_binary(actor) and is_binary(service_id) do
    with {:ok, before_state} <- RuntimeSources.service(service_id),
         {:ok, queued} <-
           RunStore.queue_service(service_id, action, actor, %{
             trigger: context[:trigger] || context["trigger"] || "api",
             node: context[:node] || context["node"] || "local-ryzen",
             before_state: snapshot(before_state)
           }),
         {:ok, running} <- RunStore.start(queued.id, actor) do
      capability = "service.#{action}"
      input = %{service_id: service_id, action: action}

      case ExecutionService.execute(capability, actor, service_id, input, context) do
        {:ok, result} ->
          after_state = observed_after(result, service_id)
          evaluation = ResultEvaluator.service(action, before_state, after_state, :ok)

          case RunStore.succeed(
                 running.id,
                 actor,
                 result_summary(action, service_id, after_state),
                 0,
                 "service:#{service_id}",
                 %{
                   after_state: snapshot(after_state),
                   evaluation: evaluation,
                   score: evaluation.score
                 }
               ) do
            {:ok, finished} -> {:ok, result, finished}
            {:error, reason} -> {:error, {:run_finalize_failed, reason}, running}
          end

        {:error, reason} ->
          after_state = observed_after(nil, service_id)
          evaluation = evaluation_for_service_error(action, before_state, after_state, reason)
          finalize_service_error(running, actor, reason, after_state, evaluation)
      end
    end
  end

  def execute_service(_action, _actor, _service_id, _context),
    do: {:error, :invalid_service_execution_request}

  defp authorize_workflow(context, workflow_id) do
    approval_id = context[:approval_id] || context["approval_id"]

    case ApprovalStore.validate(approval_id, "workflow.execute", workflow_id, "L2") do
      {:ok, _approval} -> :ok
      {:blocked, reason} -> {:error, {:approval_blocked, reason}}
      {:error, :not_found} -> {:error, :approval_required}
      {:error, reason} -> {:error, {:approval_invalid, reason}}
    end
  end

  defp execute_approved_workflow(queued, workflow_id, actor, input, context) do
    with {:ok, running} <- RunStore.start(queued.id, actor) do
      execution_input = Map.put(input, "workflow_id", workflow_id)

      case ExecutionService.execute(
             "workflow.execute",
             actor,
             workflow_id,
             execution_input,
             context
           ) do
        {:ok, result} ->
          exit_code = workflow_exit_code(result)
          evaluation = ResultEvaluator.workflow(result, exit_code)

          RunStore.succeed(
            running.id,
            actor,
            workflow_summary(result),
            exit_code,
            workflow_evidence(result),
            %{evaluation: evaluation, score: evaluation.score}
          )

        {:error, reason} ->
          evaluation = ResultEvaluator.workflow(safe_reason(reason), 1)

          if approval_error?(reason) do
            RunStore.block(running.id, actor, safe_reason(reason), %{
              evaluation: ResultEvaluator.blocked("workflow", reason),
              score: 0
            })
            |> as_approval_error(reason)
          else
            RunStore.fail(running.id, actor, safe_reason(reason), 1, %{
              evaluation: evaluation,
              score: evaluation.score
            })
            |> as_execution_error(reason)
          end
      end
    end
  end

  defp block_workflow(queued, actor, reason) do
    evaluation = ResultEvaluator.blocked("workflow", reason)

    case RunStore.block(queued.id, actor, safe_reason(reason), %{
           evaluation: evaluation,
           score: evaluation.score
         }) do
      {:ok, blocked} -> {:error, {:approval_required, blocked}}
      {:error, persist_reason} -> {:error, {:run_finalize_failed, persist_reason}}
    end
  end

  defp as_approval_error({:ok, blocked}, _reason), do: {:error, {:approval_required, blocked}}
  defp as_approval_error({:error, persist_reason}, _reason), do: {:error, {:run_finalize_failed, persist_reason}}

  defp as_execution_error({:ok, failed}, reason), do: {:error, {reason, failed}}
  defp as_execution_error({:error, persist_reason}, _reason), do: {:error, {:run_finalize_failed, persist_reason}}

  defp finalize_service_error(run, actor, reason, after_state, evaluation) do
    attrs = %{
      after_state: snapshot(after_state),
      evaluation: evaluation,
      score: evaluation.score
    }

    result = safe_reason(reason)

    persisted =
      if approval_error?(reason) do
        RunStore.block(run.id, actor, result, attrs)
      else
        RunStore.fail(run.id, actor, result, 1, attrs)
      end

    case persisted do
      {:ok, finished} -> {:error, reason, finished}
      {:error, persist_reason} -> {:error, {:run_finalize_failed, persist_reason}, run}
    end
  end

  defp evaluation_for_service_error(action, before_state, after_state, reason) do
    if approval_error?(reason) do
      ResultEvaluator.blocked("service", reason)
    else
      ResultEvaluator.service(action, before_state, after_state, :error)
    end
  end

  defp approval_error?(:approval_required), do: true
  defp approval_error?({:approval_required, _}), do: true
  defp approval_error?({:approval_blocked, _}), do: true
  defp approval_error?({:approval_invalid, _}), do: true
  defp approval_error?(_), do: false

  defp observed_after(result, service_id) when is_map(result) do
    if value(result, :active_state), do: result, else: refresh(service_id)
  end

  defp observed_after(_result, service_id), do: refresh(service_id)

  defp refresh(service_id) do
    case RuntimeSources.service(service_id) do
      {:ok, service} -> service
      {:error, _} -> %{}
    end
  end

  defp snapshot(service) when is_map(service) do
    Map.take(service, [
      :name,
      :scope,
      :active_state,
      :sub_state,
      :enabled,
      :pid,
      :uptime_seconds,
      :restart_count,
      :status,
      :health,
      :reachable
    ])
  end

  defp snapshot(_), do: %{}

  defp result_summary(action, service_id, after_state) do
    state = value(after_state, :active_state) || "unknown"
    "service #{action} completed for #{service_id}; active_state=#{state}"
  end

  defp workflow_summary(result) when is_map(result),
    do: value(result, :summary) || "governed workflow completed"

  defp workflow_summary(result) when is_binary(result), do: result
  defp workflow_summary(_), do: "governed workflow completed"

  defp workflow_exit_code(result) when is_map(result) do
    case value(result, :exit_code) do
      code when is_integer(code) -> code
      _ -> 0
    end
  end

  defp workflow_exit_code(_), do: 0

  defp workflow_evidence(result) when is_map(result), do: value(result, :evidence_ref)
  defp workflow_evidence(_), do: nil

  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason({tag, _}) when is_atom(tag), do: Atom.to_string(tag)
  defp safe_reason(_), do: "execution_failed"

  defp value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
