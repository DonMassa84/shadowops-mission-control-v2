defmodule ShadowOpsCore.ExecutionService do
  @moduledoc """
  Execution Service - central point for all governed actions.

  Flow: Request -> Actor/Identity -> Capability Registry -> Policy -> Risk -> Approval ->
  PrivacyGate -> ExecutionService -> Adapter -> Audit -> Health/Events

  Controller and LiveView MUST NOT directly call mutating adapters.
  No arbitrary-shell API.
  No client-based shell commands.
  """

  alias ShadowOpsCore.{Audit, Events, GovernanceGate}

  alias ShadowOpsCore.Adapters.{
    CanonicalWorkflowAdapter,
    Deny,
    OllamaAdapter,
    OpenCodeAdapter,
    SystemdAdapter
  }

  alias ShadowOpsCore.RuntimeSources

  @doc "Executes an action through the full governance chain."
  def execute(capability, actor, resource, input, context \\ %{}) do
    context = context |> Map.put(:actor, actor) |> Map.put(:resource, resource)

    with {:ok, authorization} <-
           GovernanceGate.authorize(capability, actor, resource, input, context) do
      execute_via_adapter(authorization.capability, input, context, authorization)
    end
  end

  defp execute_via_adapter(capability_spec, input, context, authorization) do
    policy_decision = if(authorization.approval_required, do: "APPROVED", else: "AUTO")
    context = Map.put(context, :policy_decision, policy_decision)

    Events.publish_execution(capability_spec.id, :execution_started, :success, event_input(input))

    result = dispatch(capability_spec, input, context)

    case result do
      {:ok, value} ->
        Audit.record(
          :execution_finished,
          context[:actor],
          capability_spec.id,
          :success,
          %{executor: capability_spec.executor}
        )

        Events.publish_execution(
          capability_spec.id,
          :execution_finished,
          :success,
          %{executor: capability_spec.executor}
        )

        {:ok, value}

      {:error, reason} ->
        safe_reason = safe_reason(reason)

        Audit.record(
          :execution_blocked,
          context[:actor],
          capability_spec.id,
          :blocked,
          %{executor: capability_spec.executor, reason: safe_reason}
        )

        Events.publish_execution(
          capability_spec.id,
          :execution_finished,
          :failure,
          %{executor: capability_spec.executor, reason: safe_reason}
        )

        {:error, reason}
    end
  end

  defp dispatch(%{executor: :canonical_workflow} = spec, input, context) do
    CanonicalWorkflowAdapter.execute(spec, input, context)
  end

  defp dispatch(%{executor: :service_runtime, id: capability}, input, context) do
    action = action_from_capability(capability)

    with {:ok, id} <-
           required_id(
             value(input, :service_id) || value(input, :service_name) || context[:resource],
             :service_id_required
           ),
         {:ok, service} <- RuntimeSources.service(id),
         :ok <- SystemdAdapter.validate(service) do
      case action do
        "status" ->
          {:ok, service}

        action when action in ["start", "restart"] ->
          SystemdAdapter.run(service, %{"action" => action}, context)

        "stop" ->
          SystemdAdapter.stop(service, context)

        _ ->
          {:error, :action_not_allowed}
      end
    end
  end

  defp dispatch(%{executor: :node_runtime, id: capability}, input, context) do
    action = action_from_capability(capability)

    with {:ok, id} <- required_id(value(input, :node_id) || context[:resource], :node_id_required) do
      RuntimeSources.node_action(id, action)
    end
  end

  defp dispatch(%{executor: :opencode_runtime}, input, context) do
    with {:ok, [runtime | _]} <- OpenCodeAdapter.discover(),
         :ok <- OpenCodeAdapter.validate(runtime) do
      OpenCodeAdapter.run(runtime, input, context)
    else
      {:error, _} = error -> error
    end
  end

  defp dispatch(%{executor: :ollama_runtime}, input, context) do
    with {:ok, model} <- required_id(value(input, :model), :model_required),
         {:ok, models} <- OllamaAdapter.discover(),
         {:ok, resource} <- find_model(models, model),
         :ok <- OllamaAdapter.validate(resource) do
      OllamaAdapter.run(resource, input, context)
    end
  end

  defp dispatch(spec, input, context), do: Deny.execute(spec, input, context)

  defp find_model(models, model) do
    case Enum.find(models, &(&1.name == model)) do
      nil -> {:error, :model_not_found}
      resource -> {:ok, resource}
    end
  end

  defp required_id(value, _error) when is_binary(value) and value != "", do: {:ok, value}
  defp required_id(_value, error), do: {:error, error}

  defp action_from_capability(capability) do
    capability
    |> String.split(".")
    |> List.last()
  end

  defp event_input(input) when is_map(input) do
    input
    |> Map.drop([:prompt, "prompt", :task, "task", :message, "message"])
    |> Map.put(:payload_redacted, true)
  end

  defp event_input(_), do: %{payload_redacted: true}

  defp safe_reason(reason) when is_atom(reason), do: reason
  defp safe_reason({tag, code, _detail}) when is_atom(tag), do: {tag, code}
  defp safe_reason({tag, _detail}) when is_atom(tag), do: tag
  defp safe_reason(_), do: :execution_failed

  defp value(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp value(_, _), do: nil
end
