defmodule ShadowOpsWeb.SocialUnavailableLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi
  alias ShadowOpsCore.ConnectorState
  alias WorkflowEngine.{Inventory, Registry}

  def mount(_params, _session, socket) do
    id = socket.assigns.live_action |> Atom.to_string()
    connector = connector(id)
    {workflows, inventory_status} = workflow_inventory(id)

    {:ok,
     assign(socket,
       connector: connector,
       path: "/social/" <> id,
       whatsapp?: id == "whatsapp",
       workflows: workflows,
       inventory_status: inventory_status,
       metadata: connector.metadata || %{}
     )}
  end

  def render(assigns) do
    ~H"""
    <.app_shell
      title={if(@whatsapp?, do: "WhatsApp operations", else: @connector.name)}
      subtitle="Source evidence and workflow operations"
      active={@path}
      availability={@connector.status}
      updated_at={@connector.last_sync_at}
    >
      <.source_meta
        source={@connector.source || "No source"}
        updated_at={@connector.last_sync_at}
        availability={@connector.status}
      />

      <section :if={@whatsapp?} class="mc-grid" aria-label="WhatsApp evidence">
        <.metric_card
          label="Source / import"
          value={@connector.status}
          status={@connector.status}
          source={@connector.source_type}
        />
        <.metric_card
          label="Agent database"
          value={Map.get(@metadata, :agent_runtime_status, "UNKNOWN")}
          status={Map.get(@metadata, :agent_runtime_status, "UNKNOWN")}
          source="Local database evidence; worker state unverified"
        />
        <.metric_card
          label="Registered workflows"
          value={if(@inventory_status == "AVAILABLE", do: length(@workflows), else: "Unknown")}
          status={@inventory_status}
          source="Existing WhatsApp workflow pack"
        />
      </section>

      <.panel
        :if={@whatsapp?}
        title="Next steps"
        description="An imported archive does not establish a live messaging session."
      >
        <p :if={!@connector.real_data or !@connector.reachable} class="mc-callout">
          Source evidence is incomplete. Check the configured source in
          <a href="/integrations">Integrations</a> before relying on its data.
        </p>
        <p>
          Review <a href="/workflows">runtime bindings</a> before execution.
          Registered definitions alone do not prove an active worker.
        </p>
        <p>
          Inspect <a href="/runs">run results</a>,
          <a href="/approvals">required approvals</a> and
          <a href="/audit">audit evidence</a> through the existing control plane.
          Queue drain and retry may send pending messages; inspect their scope first.
        </p>
      </.panel>

      <.panel
        :if={@whatsapp?}
        title="WhatsApp workflows"
        description="Source-defined inventory. Runtime execution and last-run evidence remain separate."
      >
        <p :if={@inventory_status == "UNAVAILABLE"} class="mc-callout" role="status">
          Workflow inventory unavailable. Check the configured registry and its validation results.
        </p>
        <p :if={@inventory_status == "NOT_CONFIGURED"} class="mc-empty">
          No WhatsApp workflow pack is configured in the loaded registry.
        </p>
        <div :if={@inventory_status == "AVAILABLE"} class="mc-table-wrap">
          <table id="whatsapp-workflows" class="mc-table">
            <caption>Registered WhatsApp workflows</caption>
            <thead>
              <tr>
                <th scope="col">Workflow</th>
                <th scope="col">Execution evidence</th>
                <th scope="col">Runtime</th>
                <th scope="col">Source risk</th>
                <th scope="col">Source approval</th>
                <th scope="col">Last run</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={workflow <- @workflows}>
                <td class="mc-mono">{workflow["id"]}</td>
                <td><.status_badge status={workflow["execution_status"]} /></td>
                <td>{workflow["runtime"] || "Unknown"}</td>
                <td>{workflow["risk_level"] || "Unknown"}</td>
                <td>{approval_label(workflow["approval_required"])}</td>
                <td>Last run not evidenced</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <.panel
        title="Connector contract"
        description="Only aggregate state is exposed; message content remains private."
      >
        <dl class="mc-dl">
          <dt>Status</dt>
          <dd><.status_badge status={@connector.status} /></dd>
          <dt>Health</dt>
          <dd>{@connector.health}</dd>
          <dt>Source type</dt>
          <dd>{@connector.source_type}</dd>
          <dt>Real data</dt>
          <dd>{@connector.real_data}</dd>
          <dt>Synthetic</dt>
          <dd>{@connector.synthetic}</dd>
          <dt>Reachable</dt>
          <dd>{@connector.reachable}</dd>
          <dt>Record count</dt>
          <dd>{@connector.record_count || "Not evidenced"}</dd>
          <dt>Last source update</dt>
          <dd>{@connector.last_sync_at || "Not evidenced"}</dd>
          <dt>Error</dt>
          <dd>{@connector.error_message || "None"}</dd>
        </dl>
      </.panel>
    </.app_shell>
    """
  end

  defp connector("whatsapp"), do: ShadowOpsApi.whatsapp()

  defp connector(id) do
    Enum.find(ShadowOpsApi.social().records, &(&1.id == id)) ||
      ConnectorState.build(%{
        id: id,
        name: String.capitalize(id),
        kind: "social",
        status: "UNAVAILABLE",
        health: "UNKNOWN",
        source_type: "UNKNOWN"
      })
  end

  defp workflow_inventory("whatsapp") do
    case Registry.load() do
      {:ok, registry} ->
        workflows =
          registry
          |> Inventory.external_workflows()
          |> Enum.filter(&(&1["source_set"] == "whatsapp_agent_pack"))

        {workflows, if(workflows == [], do: "NOT_CONFIGURED", else: "AVAILABLE")}

      {:error, _reason} ->
        {[], "UNAVAILABLE"}
    end
  end

  defp workflow_inventory(_id), do: {[], "NOT_APPLICABLE"}
  defp approval_label(true), do: "Required by source"
  defp approval_label(false), do: "Not required by source; execution policy still applies"
  defp approval_label(_), do: "Unknown"
end
