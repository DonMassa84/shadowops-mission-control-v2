defmodule ShadowOpsCore.GovernanceGate do
  @moduledoc """
  Central authorization gate for every real ShadowOps mutation.

  Registration does not imply runtime availability. This gate authorizes the request; the
  backing runtime adapter still enforces its own concrete resource/action allow-list.
  """

  alias ShadowOpsCore.{ApprovalStore, Audit, CapabilityRegistry, Policy, PrivacyGate}

  def authorize(capability, actor, resource, input, context \\ %{}) do
    with :ok <- valid_actor(actor),
         {:ok, capability_spec} <- CapabilityRegistry.lookup(capability),
         {:ok, policy} <- Policy.evaluate(capability, actor, context),
         {:ok, _audit} <- audit_policy(actor, resource, capability, policy),
         :ok <- approval(policy, capability, resource, context),
         {:ok, :allowed} <- PrivacyGate.check(input) do
      {:ok,
       %{
         capability: capability_spec,
         risk_level: policy.risk_level,
         approval_required: policy.approval_required,
         automatic_execution: policy.automatic_execution,
         effect_scope: policy.effect_scope
       }}
    else
      {:error, :blocked, reason} ->
        blocked(actor, resource, capability, {:privacy_gate_blocked, reason})

      {:blocked, reason} ->
        blocked(actor, resource, capability, {:approval_blocked, reason})

      {:error, reason} ->
        blocked(actor, resource, capability, reason)

      other ->
        blocked(actor, resource, capability, {:governance_failed, other})
    end
  end

  defp approval(%{approval_required: false}, _capability, _resource, _context), do: :ok

  defp approval(%{approval_required: true, risk_level: risk}, capability, resource, context) do
    approval_id = value(context, :approval_id)

    cond do
      not (is_binary(approval_id) and approval_id != "") ->
        {:error, :approval_required}

      true ->
        case ApprovalStore.validate(approval_id, capability, resource, risk) do
          {:ok, _approval} -> :ok
          {:blocked, reason} -> {:error, {:approval_blocked, reason}}
          {:error, reason} -> {:error, {:approval_invalid, reason}}
        end
    end
  end

  defp audit_policy(actor, resource, capability, policy) do
    Audit.record(:policy_evaluated, actor, resource, :success, %{
      capability: capability,
      risk_level: policy.risk_level,
      approval_required: policy.approval_required,
      effect_scope: policy.effect_scope
    })
  end

  defp blocked(actor, resource, capability, reason) do
    if is_binary(actor) and actor != "" do
      _ =
        Audit.record(:execution_blocked, actor, resource, :blocked, %{
          capability: capability,
          reason: inspect(reason)
        })
    end

    {:error, reason}
  end

  defp valid_actor(actor) when is_binary(actor) and byte_size(actor) in 1..120, do: :ok
  defp valid_actor(_actor), do: {:error, :valid_actor_required}

  defp value(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp value(_map, _key), do: nil
end
