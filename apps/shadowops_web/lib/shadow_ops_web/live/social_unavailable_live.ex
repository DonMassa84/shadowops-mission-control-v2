defmodule ShadowOpsWeb.SocialUnavailableLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi

  def mount(_params, _session, socket) do
    id = socket.assigns.live_action |> Atom.to_string()
    connector = Enum.find(ShadowOpsApi.social().records, &(&1.id == id))
    {:ok, assign(socket, connector: connector, path: "/social/" <> id)}
  end

  def render(assigns),
    do: ~H"""
    <.app_shell title={@connector.name} subtitle="Social connector" active={@path} availability={@connector.status} updated_at={@connector.last_sync_at}>
      <.source_meta source={@connector.source || "No source"} updated_at={@connector.last_sync_at} availability={@connector.status} />
      <.panel title="Connector contract" description="Only aggregate state is exposed; message content remains private.">
        <dl class="mc-dl"><dt>Status</dt><dd><.status_badge status={@connector.status} /></dd><dt>Health</dt><dd>{@connector.health}</dd><dt>Source type</dt><dd>{@connector.source_type}</dd><dt>Real data</dt><dd>{@connector.real_data}</dd><dt>Synthetic</dt><dd>{@connector.synthetic}</dd><dt>Reachable</dt><dd>{@connector.reachable}</dd><dt>Record count</dt><dd>{@connector.record_count || "Not evidenced"}</dd><dt>Error</dt><dd>{@connector.error_message || "None"}</dd></dl>
      </.panel>
    </.app_shell>
    """
end
