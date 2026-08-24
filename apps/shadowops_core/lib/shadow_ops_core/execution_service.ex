defmodule ShadowOpsCore.ExecutionService do
  @moduledoc """
  Execution Service - central point for all mutating actions.

  Flow: Request -> Actor/Identity -> Capability Registry -> Policy -> Risk -> Approval -> PrivacyGate -> ExecutionService -> Adapter -> Audit -> Health/Events

  Controller and LiveView MUST NOT directly call mutating adapters.
  No arbitrary-shell API.
  No client-based shell commands.
  """

  alias ShadowOpsCore.{Policy, PrivacyGate, Audit, Events, ApprovalStore, CapabilityRegistry}

  alias ShadowOpsCore.Adapters.{
    CanonicalWorkflowAdapter,
    Deny
  }

  @doc """
  Executes a mutating action through the full governance chain.
  """
  def execute(capability, actor, resource, input, context \\ %{}) do
    context = Map.put_new(context, :actor, actor)
    # 1. Capability Registry lookup
    case CapabilityRegistry.lookup(capability) do
      {:ok, capability_spec} ->
        # 2. Policy evaluation
        case Policy.evaluate(capability, actor, context) do
          {:ok, policy} ->
            # 3. Risk assessment
            _risk_level = policy.risk_level
            approval_required = policy.approval_required

            # 4. Approval check if required
            approval_result =
              if approval_required do
                check_approval(capability, actor, resource, context)
              else
                {:ok, :not_required}
              end

            case approval_result do
              {:ok, approval} when approval != :not_required ->
                # 5. PrivacyGate check
                case PrivacyGate.check(input) do
                  {:ok, :allowed} ->
                    # 6. Execute via adapter
                    execute_via_adapter(capability_spec, input, context, approval)

                  {:error, :blocked, reason} ->
                    Audit.record(:execution_blocked, actor, resource, :blocked, %{reason: reason})
                    {:error, {:privacy_gate_blocked, reason}}
                end

              {:ok, :not_required} ->
                # No approval needed, execute directly
                execute_via_adapter(capability_spec, input, context, nil)

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
    policy_decision =
      if is_nil(approval),
        do: "AUTO",
        else: "APPROVED"

    context =
      Map.put(
        context,
        :policy_decision,
        policy_decision
      )

    Events.publish_execution(
      capability_spec.id,
      :execution_started,
      :success,
      input
    )

    result =
      dispatch(
        capability_spec,
        input,
        context
      )

    case result do
      {:ok, value} ->
        Audit.record(
          :execution_completed,
          context[:actor],
          capability_spec.id,
          :success,
          %{
            executor: capability_spec.executor
          }
        )

        Events.publish_execution(
          capability_spec.id,
          :execution_finished,
          :success,
          %{
            executor: capability_spec.executor
          }
        )

        {:ok, value}

      {:error, reason} ->
        Audit.record(
          :execution_blocked,
          context[:actor],
          capability_spec.id,
          :blocked,
          %{
            executor: capability_spec.executor,
            reason: reason
          }
        )

        Events.publish_execution(
          capability_spec.id,
          :execution_finished,
          :failure,
          %{
            executor: capability_spec.executor,
            reason: reason
          }
        )

        {:error, reason}
    end
  end

  defp dispatch(
         %{executor: :canonical_workflow} = spec,
         input,
         context
       ) do
    CanonicalWorkflowAdapter.execute(
      spec,
      input,
      context
    )
  end

  defp dispatch(spec, input, context) do
    Deny.execute(spec, input, context)
  end
end
