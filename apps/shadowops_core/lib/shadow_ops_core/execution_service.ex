defmodule ShadowOpsCore.ExecutionService do
  @moduledoc """
  Execution Service - central point for all governed actions.

  Flow: Request -> Actor/Identity -> Capability Registry -> Policy -> Risk -> Approval ->
  PrivacyGate -> ExecutionService -> Adapter -> Audit -> Health/Events

  Controller and LiveView MUST NOT directly call mutating adapters.
  No arbitrary-shell API.
  No client-based shell commands.
  """

  alias ShadowOpsCore.{Policy, PrivacyGate, Audit, Events, ApprovalStore, CapabilityRegistry}

  alias ShadowOpsCore.Adapters.{
    CanonicalWorkflowAdapter,
    Deny,
    OllamaAdapter,
    OpenCodeAdapter,
    SystemdAdapter
  }

  alias ShadowOpsCore.RuntimeSources

  @doc """
  Executes an action through the full governance chain.
  """
  def execute(capability, actor, resource, input, context \\ %{}) do
    context =
      context
      |> Map.put_new(:actor, actor)
      |> Map.put_new(:resource, resource)

    case CapabilityRegistry.lookup(capability) do
      {:ok, capability_spec} ->
        case Policy.evaluate(capability, actor, context) do
          {:ok, policy} ->
            _risk_level = policy.risk_level
            approval_required = policy.approval_required

            approval_result =
              if approval_required do
                check_approval(capability, actor, resource, context)
              else
                {:ok, :not_required}
              end

            case approval_result do
              {:ok, approval} when approval != :not_required ->
                case PrivacyGate.check(input) do
                  {:ok, :allowed} ->
                    execute_via_adapter(capability_spec, input, context, approval)

                  {:error, :blocked, reason} ->
                    Audit.record(:execution_blocked, actor, resource, :blocked, %{reason: reason})
                    {:error, {:privacy_gate_blocked, reason}}
                end

              {:ok, :not_required} ->
                case PrivacyGate.check(input) do
                  {:ok, :allowed} ->
                    execute_via_adapter(capability_spec, input, context, nil)

                  {:error, :blocked, reason} ->
                    Audit.record(:execution_blocked, actor, resource, :blocked, %{reason: reason})
                    {:error, {:privacy_gate_blocked, reason}}
                end

              {:error, reason} ->
                Audit.record(:execution_blocked, actor, resource, :blocked, %{reason: reason})
                {:error, reason}
            end

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  defp check_approval(capability, _actor, resource, context) do
    approval_id = context[:approval_id]

    if is_nil(approval_id) do
      {:error, {:approval_required, "approval_id missing in context"}}
    else
      risk_level = context[:risk_level] || "L1"

      case ApprovalStore.validate(approval_id, capability, resource, risk_level) do
        {:ok, approval} ->
          {:ok, approval}

        {:error, :not_found} ->
          {:error, {:approval_required, approval_id}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp execute_via_adapter(capability_spec, input, context, approval) do
    policy_decision = if(is_nil(approval), do: "AUTO", else: "APPROVED")
    context = Map.put(context, :policy_decision, policy_decision)

    Events.publish_execution(capability_spec.id, :execution_started, :success, event_input(input))

    result = dispatch(capability_spec, input, context)

    case result do
      {:ok, value} ->
        Audit.record(
          :execution_completed,
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
        Audit.record(
          :execution_blocked,
          context[:actor],
          capability_spec.id,
          :blocked,
          %{executor: capability_spec.executor, reason: reason}
        )

        Events.publish_execution(
          capability_spec.id,
          :execution_finished,
          :failure,
          %{executor: capability_spec.executor, reason: reason}
        )

        {:error, reason}
    end
  end

  defp dispatch(%{executor: :canonical_workflow} = spec, input, context) do
    CanonicalWorkflowAdapter.execute(spec, input, context)
  end

  defp dispatch(%{executor: :service_runtime, id: capability}, input, context) do
    action = action_from_capability(capability)
    id = value(input, :service_id) || value(input, :service_name) || context[:resource]

    with true <- is_binary(id) and id != "" || {:error, :service_id_required},
         {:ok, service} <- RuntimeSources.service(id),
         :ok <- SystemdAdapter.validate(service) do
      case action do
        "status" -> {:ok, service}
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
    id = value(input, :node_id) || context[:resource]

    if is_binary(id) and id != "" do
      RuntimeSources.node_action(id, action)
    else
      {:error, :node_id_required}
    end
  end

  defp dispatch(%{executor: :opencode_runtime}, input, context) do
    with {:ok, [runtime | _]} <- OpenCodeAdapter.discover(),
         :ok <- OpenCodeAdapter.validate(runtime) do
      OpenCodeAdapter.run(runtime, input, context)
    else
      {:ok, []} -> {:error, :opencode_runtime_unavailable}
      {:error, _} = error -> error
    end
  end

  defp dispatch(%{executor: :ollama_runtime}, input, context) do
    model = value(input, :model)

    with true <- is_binary(model) and model != "" || {:error, :model_required},
         {:ok, models} <- OllamaAdapter.discover(),
         %{} = resource <- Enum.find(models, &(&1.name == model)) || {:error, :model_not_found},
         :ok <- OllamaAdapter.validate(resource) do
      OllamaAdapter.run(resource, input, context)
    else
      {:error, _} = error -> error
      false -> {:error, :model_required}
      nil -> {:error, :model_not_found}
    end
  end

  defp dispatch(spec, input, context), do: Deny.execute(spec, input, context)

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

  defp value(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp value(_, _), do: nil
end
