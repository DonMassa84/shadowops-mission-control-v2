defmodule AgentRuntime.RiskPolicy do
  @moduledoc "Policy mapping for external workflow risk levels."

  @policies %{
    "L0" => %{effect_scope: :read_only, approval_required: false, automatic_execution: true},
    "L1" => %{
      effect_scope: :local_state_change,
      approval_required: false,
      automatic_execution: true
    },
    "L2" => %{effect_scope: :external_action, approval_required: true, automatic_execution: false},
    "L3" => %{
      effect_scope: :privileged_high_risk,
      approval_required: true,
      automatic_execution: false
    }
  }

  @spec get(String.t()) :: {:ok, map()} | {:error, :unknown_risk_level}
  def get(level) when is_binary(level) do
    case Map.fetch(@policies, level) do
      {:ok, policy} -> {:ok, policy}
      :error -> {:error, :unknown_risk_level}
    end
  end
end
