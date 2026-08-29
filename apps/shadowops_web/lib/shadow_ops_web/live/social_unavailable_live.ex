defmodule ShadowOpsWeb.SocialUnavailableLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi
  alias ShadowOpsWeb.SourceRegistry

  def mount(_params, _session, socket) do
    id = socket.assigns.live_action |> Atom.to_string()
    connector = Enum.find(ShadowOpsApi.social().records, &(&1.id == id))
    source = SourceRegistry.snapshot(id)

    {:ok,
     assign(socket,
       connector: connector,
       source: source,
       path: "/social/" <> id,
       connector_id: id
     )}
  end

  def render(assigns) do
    ~H"""
    <.app_shell title={@connector.name} subtitle="Social connector" active={@path} availability={@connector.status} updated_at={@connector.last_sync_at}>
      <.source_meta source={@connector.source || "No source"} updated_at={@connector.last_sync_at} availability={@connector.status} />

      <.panel title="Capability State" description="Evidence-backed status for this social connector.">
        <.capability_card
          title={@connector.name}
          state={capability_state(@connector, @source)}
          mode={connector_mode(@connector, @source)}
          real_data={@source.real_data}
          reachable={@source.reachable}
          synthetic={@source.synthetic}
          runtime={@connector.source_type}
          approval={@source.secret_binding.state}
          evidence={@connector.error_message || @source.error_message || "No evidence"}
          last_probe={@source.last_sync || @connector.last_sync_at}
          unlock_requirement={unlock_requirement(@connector, @source)}
        />
      </.panel>

      <.panel title="Evidence" description="Available evidence for this connector.">
        <dl class="mc-dl">
          <dt>Status</dt><dd><.status_badge status={@connector.status} /></dd>
          <dt>Health</dt><dd>{@connector.health}</dd>
          <dt>Source type</dt><dd>{@connector.source_type}</dd>
          <dt>Real data</dt><dd><.status_badge status={if(@source.real_data, do: "YES", else: "NO")} /></dd>
          <dt>Synthetic</dt><dd><.status_badge status={if(@source.synthetic, do: "YES", else: "NO")} /></dd>
          <dt>Reachable</dt><dd><.status_badge status={if(@source.reachable, do: "YES", else: "NO")} /></dd>
          <dt>Record count</dt><dd>{@source.record_count || @connector.record_count || "Not evidenced"}</dd>
          <dt>Last sync</dt><dd>{@source.last_sync || @connector.last_sync_at || "Not evidenced"}</dd>
          <dt>Error</dt><dd>{@connector.error_message || @source.error_message || "None"}</dd>
          <dt>Secrets</dt><dd><.status_badge status={@source.secret_binding.state} /></dd>
        </dl>
      </.panel>

      <.panel :if={@source.status in ["NOT_CONFIGURED", "UNAVAILABLE"]} title="Configuration" description="Steps to enable this connector.">
        <ul>
          <li>Add import evidence file: <code>~/.local/share/shadowops/imports/{@connector_id}.json</code></li>
          <li>Configure required OAuth secrets: #{inspect(@source.secret_binding.required)}</li>
          <li>Run connector sync to generate evidence</li>
        </ul>
      </.panel>
    </.app_shell>
    """
  end

  defp capability_state(_connector, source) do
    cond do
      source.real_data and source.reachable and not source.synthetic -> "READY"
      source.status in ["NOT_CONFIGURED", "UNAVAILABLE"] -> "CONFIGURATION_REQUIRED"
      source.status == "DEGRADED" -> "DEGRADED"
      source.synthetic -> "SYNTHETIC"
      true -> "PARTIAL"
    end
  end

  defp connector_mode(_connector, source) do
    cond do
      source.synthetic -> "SYNTHETIC"
      source.real_data and source.reachable and not source.synthetic -> "LIVE"
      source.real_data and not source.reachable -> "READ_ONLY"
      true -> "UNKNOWN"
    end
  end

  defp unlock_requirement(_connector, source) do
    case source.status do
      "NOT_CONFIGURED" -> "Add import evidence file and configure OAuth secrets"
      "UNAVAILABLE" -> "Verify connector runtime and generate evidence"
      "DEGRADED" -> "Check API reachability and authentication"
      _ -> "Verify evidence and configuration"
    end
  end
end
