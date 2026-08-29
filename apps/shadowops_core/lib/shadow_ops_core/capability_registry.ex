defmodule ShadowOpsCore.CapabilityRegistry do
  @moduledoc """
  Capability Registry - canonical mutation/read capability definitions used by governance.

  A capability being registered never means the backing integration is available. Runtime
  adapters remain responsible for evidence-backed availability and allow-list enforcement.
  """

  @capabilities %{
    "workflow.execute" => %{
      id: "workflow.execute",
      executor: :canonical_workflow,
      args: [:workflow_id, :input]
    },
    "node.status" => %{id: "node.status", executor: :node_runtime, args: [:node_id]},
    "node.start" => %{id: "node.start", executor: :node_runtime, args: [:node_id]},
    "node.stop" => %{id: "node.stop", executor: :node_runtime, args: [:node_id]},
    "service.status" => %{
      id: "service.status",
      executor: :service_runtime,
      args: [:service_id]
    },
    "service.start" => %{
      id: "service.start",
      executor: :service_runtime,
      args: [:service_id]
    },
    "service.stop" => %{
      id: "service.stop",
      executor: :service_runtime,
      args: [:service_id]
    },
    "service.restart" => %{
      id: "service.restart",
      executor: :service_runtime,
      args: [:service_id]
    },
    "systemd.restart" => %{
      id: "systemd.restart",
      executor: :service_runtime,
      args: [:service_name]
    },
    "systemd.start" => %{id: "systemd.start", executor: :service_runtime, args: [:service_name]},
    "systemd.stop" => %{id: "systemd.stop", executor: :service_runtime, args: [:service_name]},
    "systemd.status" => %{id: "systemd.status", executor: :service_runtime, args: [:service_name]},
    "shadowctl.run" => %{id: "shadowctl.run", executor: :not_connected, args: [:workflow_id]},
    "ollama.generate" => %{
      id: "ollama.generate",
      executor: :not_connected,
      args: [:model, :prompt]
    },
    "local_agent.invoke" => %{
      id: "local_agent.invoke",
      executor: :not_connected,
      args: [:agent_id, :task]
    },
    "opencode.execute" => %{
      id: "opencode.execute",
      executor: :opencode_runtime,
      args: [:prompt, :project_dir]
    },
    "telegram.send" => %{
      id: "telegram.send",
      executor: :not_connected,
      args: [:chat_id, :message]
    },
    "workflow.run" => %{id: "workflow.run", executor: :canonical_workflow, args: [:workflow_id]},
    "gmail.read" => %{id: "gmail.read", executor: :gmail, args: []},
    "gmail.classify" => %{id: "gmail.classify", executor: :gmail, args: [:metadata]},
    "gmail.attachment" => %{id: "gmail.attachment", executor: :gmail, args: [:message_ref]},
    "gmail.label" => %{id: "gmail.label", executor: :gmail, args: [:thread_ref, :label]},
    "gmail.create_draft" => %{id: "gmail.create_draft", executor: :gmail, args: [:thread_ref]},
    "gmail.send" => %{id: "gmail.send", executor: :gmail, args: [:draft_ref]},
    "gmail.forward" => %{id: "gmail.forward", executor: :gmail, args: [:thread_ref]},
    "gmail.delete" => %{id: "gmail.delete", executor: :gmail, args: [:thread_ref]},
    "github.export" => %{id: "github.export", executor: :github_data, args: []},
    "github.sync" => %{id: "github.sync", executor: :github_data, args: []},
    "pdf_governance.read" => %{id: "pdf_governance.read", executor: :local_evidence, args: []},
    "pdf_governance.publish" => %{
      id: "pdf_governance.publish",
      executor: :not_connected,
      args: [:channel],
      approval_required: true,
      risk_level: "L2"
    },
    "repo_governance.read" => %{id: "repo_governance.read", executor: :local_evidence, args: []},
    "repo_governance.publish" => %{
      id: "repo_governance.publish",
      executor: :not_connected,
      args: [:channel],
      approval_required: true,
      risk_level: "L2"
    }
  }

  @doc "Looks up a capability specification."
  def lookup(capability) do
    case Map.fetch(@capabilities, capability) do
      {:ok, spec} -> {:ok, spec}
      :error -> {:error, {:unknown_capability, capability}}
    end
  end

  @doc "Lists all capabilities."
  def list, do: Map.values(@capabilities)
end
