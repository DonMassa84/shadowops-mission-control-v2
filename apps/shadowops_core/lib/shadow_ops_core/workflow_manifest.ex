defmodule ShadowOpsCore.WorkflowManifest do
  @moduledoc "Canonical workflow manifest projected from the existing registry; never a parallel registry."

  alias ShadowOpsCore.Policy

  @derive Jason.Encoder
  @enforce_keys [
    :id,
    :name,
    :source,
    :runtime,
    :executor,
    :target,
    :risk_level,
    :approval_required,
    :inputs,
    :outputs,
    :connectors,
    :privacy,
    :evidence_required,
    :synthetic
  ]
  defstruct [
    :id,
    :name,
    :source,
    :runtime,
    :executor,
    :target,
    :risk_level,
    :approval_required,
    :inputs,
    :outputs,
    :connectors,
    :privacy,
    :evidence_required,
    :synthetic,
    metadata: %{}
  ]

  def from_registry(id, workflow) when is_binary(id) and is_map(workflow) do
    runtime = workflow["runtime"] || workflow["target_runtime"] || "unknown"
    source = source(runtime, workflow)
    risk = workflow["risk_level"] || workflow["risk"] || default_risk(source)

    with {:ok, policy} <- Policy.evaluate_action("workflow.run", %{risk_level: risk}) do
      manifest = %__MODULE__{
        id: id,
        name: workflow["name"] || humanize(id),
        source: source,
        runtime: %{type: runtime_type(runtime, source), value: runtime},
        executor: executor(source),
        target: workflow["target"] || target(runtime, source),
        risk_level: risk,
        approval_required: policy.decision == "APPROVAL_REQUIRED",
        inputs: workflow["inputs"] || [],
        outputs: workflow["outputs"] || [],
        connectors: workflow["connectors"] || %{},
        privacy: workflow["privacy"] || %{raw_data: "local_only", github: "metadata_only"},
        evidence_required: get_in(workflow, ["evidence", "required"]) != false,
        synthetic: workflow["synthetic"] == true,
        metadata: %{
          registry_status: workflow["status"],
          domain: workflow["domain"],
          definition: workflow["definition"],
          trusted_argv: workflow["argv"],
          trusted_argv?: Map.has_key?(workflow, "argv")
        }
      }

      {:ok, manifest}
    end
  end

  def from_registry(_, _), do: {:error, :invalid_workflow_definition}

  defp source("github_actions", _workflow), do: "github_actions"

  defp source(runtime, workflow) when is_binary(runtime) do
    cond do
      String.ends_with?(workflow["definition"] || "", ".service") -> "systemd"
      Path.type(runtime) == :absolute -> "local_script"
      runtime == "elixir" -> "local"
      runtime == "hybrid" -> "local"
      true -> runtime
    end
  end

  defp default_risk("github_actions"), do: "L2"
  defp default_risk("local_script"), do: "L2"
  defp default_risk("systemd"), do: "L2"
  defp default_risk(_), do: "L2"
  defp executor("github_actions"), do: "GitHubActionsAdapter"
  defp executor("systemd"), do: "SystemdAdapter"
  defp executor("local_script"), do: "ScriptAdapter"
  defp executor(source), do: source <> "Adapter"
  defp runtime_type("github_actions", _), do: "github_actions"
  defp runtime_type(_runtime, "systemd"), do: "systemd"
  defp runtime_type(_runtime, "local_script"), do: "local_script"
  defp runtime_type(runtime, _), do: runtime
  defp target("github_actions", _), do: "github"
  defp target(_runtime, "systemd"), do: "ryzen"
  defp target(_runtime, "local_script"), do: "ryzen"
  defp target(_, _), do: "local"

  defp humanize(id),
    do:
      id |> String.replace("_", " ") |> String.split() |> Enum.map_join(" ", &String.capitalize/1)
end
