defmodule ShadowOpsWeb.ComputeLive do
  use Phoenix.LiveView

  import ShadowOpsWeb.MissionControlComponents

  alias ShadowOpsCore.{JobQueue, Node}
  alias ShadowOpsWeb.{NodeCatalog, OneClick}

  @refresh_ms 15_000

  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_ms)
    {:ok, load(socket)}
  end

  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, load(socket)}
  end

  def handle_event("node_action", %{"id" => node_id, "action" => action}, socket) do
    if action in allowed_actions(node_id) do
      case OneClick.execute_node(action, node_id) do
        {:ok, _result} ->
          {:noreply,
           socket |> load() |> put_flash(:info, "Node action completed: #{node_id} / #{action}")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Node action blocked: #{safe_reason(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Node action is not activated for this runtime")}
    end
  end

  def render(assigns) do
    ~H"""
    <.app_shell
      title="Compute Center"
      subtitle="Physical nodes, workload queue and governed runtime actions"
      active="/compute"
      availability={@nodes.status}
      updated_at={@updated_at}
    >
      <div class="mc-grid">
        <.metric_card label="Physical nodes" value={length(@physical_nodes)} status={node_status(@physical_nodes)} source={@nodes.source} note="Logical project nodes are excluded" />
        <.metric_card label="Reachable" value={Enum.count(@physical_nodes, & &1.reachable)} status={node_status(@physical_nodes)} note="Evidence-backed node reachability" />
        <.metric_card label="Job queue" value={@jobs.status} status={@jobs.status} source={@jobs.source} note={@jobs.error_message || "Persistent Oban workload queue"} />
        <.metric_card label="Visible jobs" value={@jobs.record_count || 0} status={@jobs.status} note="Private job arguments are not rendered" />
      </div>

      <p class="mc-callout">
        One-click mode: <strong>{if(@one_click_ready, do: "READY", else: "WRITE TOKEN REQUIRED")}</strong> · every activated node action is a direct button; unavailable actions stay hidden.
      </p>

      <.panel title="Physical compute" description="Only runtime-backed nodes. Controls fail closed through policy, approval when required, execution adapters and audit.">
        <div :if={@physical_nodes != []} class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Node</th><th>Status</th><th>Reachable</th><th>Load</th><th>RAM</th><th>Uptime</th><th>Source</th><th>One click</th></tr></thead>
            <tbody>
              <tr :for={node <- @physical_nodes}>
                <td><strong>{node.name}</strong><br /><span class="mc-mono mc-muted">{Node.id(node)}</span></td>
                <td><.status_badge status={node.status} /></td>
                <td>{if(node.reachable, do: "Yes", else: "No")}</td>
                <td>{format_value(node[:load])}</td>
                <td>{format_value(node[:ram])}</td>
                <td>{node[:uptime_seconds] || "Not measured"}</td>
                <td class="mc-mono">{node.source}</td>
                <td class="mc-actions">
                  <button class="mc-button" type="button" phx-click="node_action" phx-value-id={Node.id(node)} phx-value-action="status" disabled={!@one_click_ready}>↻ Check</button>
                  <button :if={"start" in allowed_actions(Node.id(node))} class="mc-button" type="button" phx-click="node_action" phx-value-id={Node.id(node)} phx-value-action="start" disabled={!@one_click_ready}>▶ Start</button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={@physical_nodes == []} class="mc-empty">No physical runtime nodes were discovered.</p>
      </.panel>

      <.panel title="Persistent workload queue" description="Oban jobs when persistence is enabled. Scheduling state remains explicit when persistence is disabled.">
        <div :if={@jobs.records != []} class="mc-table-wrap">
          <table class="mc-table"><thead><tr><th>Job</th><th>Queue</th><th>Worker</th><th>State</th><th>Attempt</th><th>Scheduled</th></tr></thead><tbody><tr :for={job <- Enum.take(@jobs.records, 20)}><td class="mc-mono">{job.id}</td><td>{job.queue}</td><td class="mc-mono">{job.worker}</td><td><.status_badge status={String.upcase(job.state)} /></td><td>{job.attempt}/{job.max_attempts}</td><td>{time(job.scheduled_at)}</td></tr></tbody></table>
        </div>
        <p :if={@jobs.records == []} class="mc-empty">{@jobs.error_message || "No persistent jobs are currently queued."}</p>
        <p><a class="mc-button" href="/jobs">Open full job queue</a></p>
      </.panel>
    </.app_shell>
    """
  end

  defp load(socket) do
    nodes = NodeCatalog.snapshot()
    physical_nodes = Enum.reject(nodes.records, &Node.logical?/1)

    assign(socket,
      nodes: nodes,
      physical_nodes: physical_nodes,
      jobs: JobQueue.snapshot(),
      one_click_ready: OneClick.available?(),
      updated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    )
  end

  defp allowed_actions("i7"), do: ["status", "start"]
  defp allowed_actions(_), do: ["status"]

  defp node_status([]), do: "UNAVAILABLE"

  defp node_status(nodes) do
    ready = Enum.count(nodes, &(&1.status in ["READY", "ONLINE"]))

    cond do
      ready == length(nodes) -> "READY"
      ready > 0 -> "DEGRADED"
      true -> "UNAVAILABLE"
    end
  end

  defp format_value(nil), do: "Not measured"
  defp format_value(value) when is_binary(value) or is_number(value), do: to_string(value)
  defp format_value(value), do: inspect(value)
  defp time(nil), do: "Not scheduled"
  defp time(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp time(value), do: to_string(value)
  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason({tag, _}) when is_atom(tag), do: Atom.to_string(tag)
  defp safe_reason(_), do: "action_failed"
end
