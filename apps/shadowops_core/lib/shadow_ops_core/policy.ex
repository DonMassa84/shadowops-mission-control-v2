defmodule ShadowOpsCore.Policy do
  @moduledoc """
  Policy evaluation - decides IF an action is allowed based on risk.

  Separated from PrivacyGate (which decides IF data can cross trust boundary).
  """

  alias ShadowOpsCore.RiskPolicy

  @local_ai_capabilities ~w(ollama.generate)

  @doc """
  Evaluates a capability request against policy.
  Returns {:ok, risk_level} or {:error, reason}.
  """
  def evaluate(capability, _actor, _context) when capability in @local_ai_capabilities,
    do: {:error, :local_ai_forbidden}

  def evaluate(capability, _actor, context \\ %{}) do
    risk_level = RiskPolicy.infer_risk(capability, context)

    case RiskPolicy.get(risk_level) do
      {:ok, policy} ->
        {:ok, Map.put(policy, :risk_level, risk_level)}

      {:error, _} = error ->
        error
    end
  end

  @doc "Returns AUTO, APPROVAL_REQUIRED, or fails closed for an unknown action/risk."
  def evaluate_action(action, _context) when action in @local_ai_capabilities,
    do: {:error, :local_ai_forbidden}

  def evaluate_action(action, context \\ %{}) do
    risk_level = RiskPolicy.infer_risk(action, context)

    with {:ok, policy} <- RiskPolicy.get(risk_level) do
      decision = if(policy.approval_required, do: "APPROVAL_REQUIRED", else: "AUTO")

      {:ok,
       policy
       |> Map.put(:risk_level, risk_level)
       |> Map.put(:risk, risk_level)
       |> Map.put(:decision, decision)}
    else
      _ -> {:error, :unknown_policy}
    end
  end

  @doc """
  Determines if approval is required for a given risk level.
  """
  def approval_required?(risk_level) do
    case RiskPolicy.get(risk_level) do
      {:ok, policy} -> policy.approval_required
      {:error, _} -> true
    end
  end

  @doc """
  Determines if automatic execution is allowed for a given risk level.
  """
  def auto_execution_allowed?(risk_level) do
    case RiskPolicy.get(risk_level) do
      {:ok, policy} -> policy.automatic_execution
      {:error, _} -> false
    end
  end

  @doc """
  Gets the effect scope for a risk level.
  """
  def effect_scope(risk_level) do
    case RiskPolicy.get(risk_level) do
      {:ok, policy} -> policy.effect_scope
      {:error, _} -> :unknown
    end
  end
end
