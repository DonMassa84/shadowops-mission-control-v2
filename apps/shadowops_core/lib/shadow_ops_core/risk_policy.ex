defmodule ShadowOpsCore.RiskPolicy do
  @moduledoc """
  Risk level policy definitions.

  L0: read_only, no approval, auto execution
  L1: local_state_change, no approval, auto execution
  L2: external_action, approval required, no auto execution
  L3: privileged_high_risk, approval required, no auto execution
  """

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

  @capability_risks %{
    "gmail.read" => "L0",
    "gmail.classify" => "L0",
    "gmail.label" => "L1",
    "gmail.create_draft" => "L1",
    "gmail.send" => "L2",
    "gmail.forward" => "L2",
    "gmail.delete" => "L3",
    "service.status" => "L0",
    "service.start" => "L1",
    "service.restart" => "L1",
    "service.stop" => "L2",
    "systemd.status" => "L0",
    "systemd.start" => "L1",
    "systemd.restart" => "L1",
    "systemd.stop" => "L2",
    "node.status" => "L0",
    "node.start" => "L1",
    "node.stop" => "L2",
    "ollama.generate" => "L0",
    "opencode.execute" => "L2",
    "local_agent.invoke" => "L2",
    "shadowctl.run" => "L2",
    "telegram.send" => "L2",
    "workflow.run" => "L2",
    "workflow.execute" => "L2",
    "github.export" => "L1",
    "github.sync" => "L2",
    "whatsapp.ingest" => "L0",
    "whatsapp.analysis" => "L0",
    "pdf_governance.read" => "L0",
    "local_workflow.verify_runtime" => "L1",
    "local_workflow.record_test" => "L1",
    "local_workflow.map_governance" => "L2",
    "local_workflow.enable_execution" => "L2"
  }

  @spec get(String.t()) :: {:ok, map()} | {:error, :unknown_risk_level}
  def get(level) when is_binary(level) do
    case Map.fetch(@policies, level) do
      {:ok, policy} -> {:ok, policy}
      :error -> {:error, :unknown_risk_level}
    end
  end

  def get(_), do: {:error, :unknown_risk_level}

  @doc """
  Infers risk level from capability name and context.
  """
  def infer_risk(capability, context \\ %{}) do
    explicit = Map.get(context, :risk_level) || Map.get(context, "risk_level")

    cond do
      explicit in ~w(L0 L1 L2 L3) -> explicit
      is_binary(capability) -> Map.get(@capability_risks, capability, :unknown)
      true -> :unknown
    end
  end

  @doc """
  Returns all known risk levels.
  """
  def levels, do: Map.keys(@policies) |> Enum.sort()
end
