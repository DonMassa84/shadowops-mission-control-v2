defmodule ShadowOpsCore.ExecutionTracker do
  @moduledoc """
  Records governed service actions as durable execution runs and evaluates their observed result.

  This module never calls runtime adapters directly. Every mutation goes through ExecutionService.
  """

  alias ShadowOpsCore.{ExecutionService, ResultEvaluator, RunStore, RuntimeSources}

  @service_actions ["start", "restart", "stop"]

  def execute_service(action, actor, service_id, context \\ %{})
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
          evaluation = evaluation_for_error(action, before_state, after_state, reason)
          finalize_error(running, actor, reason, after_state, evaluation)
      end
    end
  end

  def execute_service(_action, _actor, _service_id, _context),
    do: {:error, :invalid_service_execution_request}

  defp finalize_error(run, actor, reason, after_state, evaluation) do
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

  defp evaluation_for_error(action, before_state, after_state, reason) do
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

  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason({tag, _}) when is_atom(tag), do: Atom.to_string(tag)
  defp safe_reason(_), do: "service_execution_failed"

  defp value(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
