defmodule ShadowOpsWeb.NodesLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents

  alias ShadowOpsCore.{Node, Truthfulness}
  alias ShadowOpsWeb.NodeCatalog

  def mount(_, _, socket) do
    data = NodeCatalog.snapshot()
    physical_nodes = Enum.reject(data.records, &Node.logical?/1)
    chatgpt_nodes = Enum.filter(data.records, &Node.logical?/1)

    {:ok,
     assign(socket,
       data: data,
       physical_nodes: physical_nodes,
       chatgpt_nodes: chatgpt_nodes,
       reachable_nodes: Enum.count(data.records, & &1.reachable)
     )}
  end

  def render(assigns) do
    ~H"""
    <.app_shell
      title="Nodes"
      subtitle="Physical hosts and governed ChatGPT project nodes"
      active="/nodes"
      availability={@data.status}
      updated_at={@data.updated_at}
    >
      <.source_meta
        source={@data.source}
        updated_at={@data.updated_at}
        availability={@data.status}
      />

      <div class="mc-grid">
        <.metric_card
          label="Physical nodes"
          value={length(@physical_nodes)}
          status={if(@physical_nodes == [], do: "UNAVAILABLE", else: "READY")}
          note="Measured local or remote infrastructure"
        />
        <.metric_card
          label="ChatGPT nodes"
          value={length(@chatgpt_nodes)}
          status={if(@chatgpt_nodes == [], do: "NOT_CONFIGURED", else: "AVAILABLE")}
          note="Logical nodes from the local federated catalog"
        />
        <.metric_card
          label="Reachable"
          value={@reachable_nodes}
          status={if(@reachable_nodes > 0, do: "READY", else: "UNAVAILABLE")}
          note="Evidence-backed reachability only"
        />
        <.metric_card
          label="ChatGPT controls"
          value="Status only"
          status="VERIFIED"
          note="Start and stop remain blocked by governance"
        />
      </div>

      <.panel
        title="Physical infrastructure"
        description="Runtime-backed hosts. Unavailable machines remain visible and are never promoted to READY without evidence."
      >
        <div :if={@physical_nodes == []} class="mc-empty">No physical nodes were discovered.</div>
        <div :if={@physical_nodes != []} class="mc-table-wrap">
          <table class="mc-table">
            <thead>
              <tr>
                <th>Node</th>
                <th>Status</th>
                <th>Health</th>
                <th>Reachable</th>
                <th>Load</th>
                <th>RAM</th>
                <th>Uptime</th>
                <th>Source</th>
                <th>Error</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={node <- @physical_nodes}>
                <td>
                  <strong>{node.name}</strong>
                  <div class="mc-muted mc-mono">{node.node_id}</div>
                </td>
                <td><.status_badge status={node.status} /></td>
                <td>{node.health}</td>
                <td>{if(node.reachable, do: "Yes", else: "No")}</td>
                <td>{inspect(node[:load])}</td>
                <td>{inspect(node[:ram])}</td>
                <td>{node[:uptime_seconds] || "Not measured"}</td>
                <td class="mc-mono">{node.source}</td>
                <td>{node.error_message || "None"}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <.panel
        title="ChatGPT project nodes"
        description="Logical project nodes derived from the local federated catalog. They do not represent a remote ChatGPT runtime connection."
      >
        <div :if={@chatgpt_nodes == []} class="mc-empty">
          No evidenced ChatGPT project nodes are configured.
        </div>
        <div :if={@chatgpt_nodes != []} class="mc-table-wrap">
          <table class="mc-table">
            <thead>
              <tr>
                <th>Project node</th>
                <th>Status</th>
                <th>Evidence</th>
                <th>Integration</th>
                <th>Content</th>
                <th>Controls</th>
                <th>Last sync</th>
                <th>Error</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={node <- @chatgpt_nodes}>
                <td>
                  <strong>{node.name}</strong>
                  <div class="mc-muted mc-mono">{node.node_id}</div>
                </td>
                <td><.status_badge status={node.status} /></td>
                <td>
                  <.status_badge
                    status={if(Truthfulness.ready?(node), do: "VERIFIED", else: "NOT_CONFIGURED")}
                  />
                </td>
                <td>{node.metadata.integration_mode}</td>
                <td>{if(node.metadata.content_ingested, do: "Ingested", else: "Reference only")}</td>
                <td>{Enum.join(node.metadata.control_actions, ", ")}</td>
                <td>{node.last_sync_at || "Not measured"}</td>
                <td>{node.error_message || "None"}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>
    </.app_shell>
    """
  end
end
