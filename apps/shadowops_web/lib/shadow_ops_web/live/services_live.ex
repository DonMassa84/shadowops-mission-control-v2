defmodule ShadowOpsWeb.ServicesLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi
  alias ShadowOpsCore.{LocalIntegrationCandidates, ServiceClassificationProjection}
  alias ShadowOpsWeb.OneClick

  def mount(_params, _session, socket) do
    data = ShadowOpsApi.services()
    runtime_snapshot = data.services
    classified = ServiceClassificationProjection.project(data, runtime_snapshot)
    candidates = LocalIntegrationCandidates.snapshot()
    filters = %{"scope" => "", "state" => "", "source" => ""}

    {:ok,
     assign(socket,
       data: classified,
       services: classified.services,
       candidates: candidates,
       filters: filters,
       last_run: nil,
       one_click_ready: OneClick.available?()
     )}
  end

  def handle_event("filter", params, socket) do
    filters =
      Map.merge(socket.assigns.filters, Map.take(params, Map.keys(socket.assigns.filters)))

    rows =
      Enum.filter(socket.assigns.data.services, fn row ->
        matches_filter?(Map.get(row, :scope, ""), filters["scope"]) and
          matches_filter?(Map.get(row, :active_state, ""), filters["state"]) and
          matches_filter?(Map.get(row, :source, ""), filters["source"])
      end)

    {:noreply, assign(socket, filters: filters, services: rows)}
  end

  def handle_event("operate", %{"id" => service_id, "action" => action}, socket) do
    case OneClick.execute_service(action, service_id) do
      {:ok, _result, run} ->
        data = ShadowOpsApi.services()
        runtime_snapshot = data.services
        classified = ServiceClassificationProjection.project(data, runtime_snapshot)

        {:noreply,
         socket
         |> assign(
           data: classified,
           services: filter_services(classified.services, socket.assigns.filters),
           candidates: LocalIntegrationCandidates.snapshot(),
           last_run: run,
           one_click_ready: OneClick.available?()
         )
         |> put_flash(
           :info,
           "#{service_id}: #{action} completed · #{run.evaluation.verdict} #{run.score}/100"
         )}

      {:error, reason, run} ->
        {:noreply,
         socket
         |> assign(last_run: run)
         |> put_flash(:error, "Service action blocked/failed: #{safe_reason(reason)}")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Service action unavailable: #{safe_reason(reason)}")}
    end
  end

  def render(assigns) do
    ~H"""
    <.app_shell title="Services" subtitle="Governed local runtime control and evaluation" active="/services" availability={@data.availability} updated_at={@data.updated_at}>
      <.source_meta source={@data.source} updated_at={@data.updated_at} availability={@data.availability} />

      <p class="mc-callout">
        One-click mode: <strong>{if(@one_click_ready, do: "READY", else: "WRITE TOKEN REQUIRED")}</strong> · Start, restart and stop are explicit operator decisions and remain policy/approval/audit gated.
      </p>

      <.panel title="Service records" description="Every supported mutation is a direct button on the runtime row; no credential or approval-ID form is required.">
        <form id="service-filters" class="mc-filter" phx-change="filter"><label>Scope<select name="scope"><option value="">All</option><option :for={v <- values(@data.services, :scope)} value={v}>{v}</option></select></label><label>State<select name="state"><option value="">All</option><option :for={v <- values(@data.services, :active_state)} value={v}>{v}</option></select></label><label>Source<select name="source"><option value="">All</option><option :for={v <- values(@data.services, :source)} value={v}>{v}</option></select></label></form>
        <div :if={@services != []} class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Service</th><th>Scope</th><th>Stage</th><th>Runtime</th><th>Live</th><th>Connected</th><th>Data</th><th>Governance</th><th>Ready</th><th>One click</th></tr></thead><tbody><tr :for={row <- @services}><td class="mc-mono">{row.name}</td><td>{row.scope}</td><td><.classification_badge stage={row.classification_stage} /></td><td class="mc-mono">{row.runtime_identity || "—"}</td><td>{yes_no(row.live)}</td><td>{yes_no(row.connected)}</td><td>{yes_no(row.real_data)}</td><td>{if(row.definition_match, do: "Mapped", else: "Reference only")}</td><td><.ready_badge ready={row.ready} /></td><td class="mc-actions"><button class="mc-button" type="button" phx-click="operate" phx-value-id={service_id(row)} phx-value-action="start" disabled={!@one_click_ready}>▶ Start</button><button class="mc-button" type="button" phx-click="operate" phx-value-id={service_id(row)} phx-value-action="restart" disabled={!@one_click_ready}>↻ Restart</button><button class="mc-button" type="button" phx-click="operate" phx-value-id={service_id(row)} phx-value-action="stop" disabled={!@one_click_ready}>■ Stop</button></td></tr></tbody></table></div><p :if={@services == []} class="mc-empty">No service records match the current filters.</p>
        <p :if={@last_run} class="mc-callout">
          Last run: <a href={"/runs/#{@last_run.id}"} class="mc-mono">{@last_run.id}</a>
          · <strong>{@last_run.status}</strong>
          · score {@last_run.score || "—"}/100
        </p>
      </.panel>

      <.panel title="Local integration candidates" description="Bounded local folder discovery. DISCOVERED means local metadata exists; it does not grant execution authority or imply READY.">
        <p class="mc-callout">
          {@candidates.counts.known_discovered}/{@candidates.counts.known_total} fixed candidates discovered ·
          {@candidates.counts.auto_discovered} additional entrypoints auto-discovered ·
          actions disabled for all candidate records
        </p>
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Name</th><th>Kind</th><th>Domain</th><th>Priority</th><th>Status</th><th>Discovery</th><th>Source ref</th><th>Evidence</th><th>Action</th></tr></thead>
            <tbody>
              <tr :for={row <- @candidates.records}>
                <td>{row.name}</td>
                <td class="mc-mono">{row.kind}</td>
                <td>{row.domain}</td>
                <td>{row.priority}</td>
                <td><.status_badge status={row.status} /></td>
                <td>{row.discovery_mode}</td>
                <td class="mc-mono">{row.source_ref}</td>
                <td>{Enum.join(row.evidence, ", ")}</td>
                <td><a class="mc-button" href="/integrations">Open source</a></td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>
    </.app_shell>
    """
  end

  defp classification_badge(%{stage: "READY"} = assigns) do
    ~H"""
    <span class="mc-badge mc-badge--green">READY</span>
    """
  end

  defp classification_badge(%{stage: "RUNTIME_VERIFIED"} = assigns) do
    ~H"""
    <span class="mc-badge mc-badge--blue">RUNTIME_VERIFIED</span>
    """
  end

  defp classification_badge(%{stage: "LIVE"} = assigns) do
    ~H"""
    <span class="mc-badge mc-badge--yellow">LIVE</span>
    """
  end

  defp classification_badge(%{stage: "CONNECTED"} = assigns) do
    ~H"""
    <span class="mc-badge mc-badge--yellow">CONNECTED</span>
    """
  end

  defp classification_badge(%{stage: "REAL_DATA"} = assigns) do
    ~H"""
    <span class="mc-badge mc-badge--yellow">REAL_DATA</span>
    """
  end

  defp classification_badge(%{stage: "DISCOVERED"} = assigns) do
    ~H"""
    <span class="mc-badge mc-badge--gray">DISCOVERED</span>
    """
  end

  defp classification_badge(assigns) do
    ~H"""
    <span class="mc-badge mc-badge--gray">{@stage || "UNKNOWN"}</span>
    """
  end

  defp ready_badge(%{ready: true} = assigns) do
    ~H"""
    <span class="mc-badge mc-badge--green">READY</span>
    """
  end

  defp ready_badge(assigns) do
    ~H"""
    <span class="mc-badge mc-badge--gray">—</span>
    """
  end

  defp yes_no(true), do: "Yes"
  defp yes_no(_), do: "No"

  defp filter_services(rows, filters) do
    Enum.filter(rows, fn row ->
      matches_filter?(Map.get(row, :scope, ""), filters["scope"]) and
        matches_filter?(Map.get(row, :active_state, ""), filters["state"]) and
        matches_filter?(Map.get(row, :source, ""), filters["source"])
    end)
  end

  defp service_id(row), do: "#{Map.get(row, :scope, "unknown")}:#{row.name}"
  defp matches_filter?(_value, ""), do: true
  defp matches_filter?(value, filter), do: value == filter
  defp values(rows, key), do: rows |> Enum.map(&Map.fetch!(&1, key)) |> Enum.uniq() |> Enum.sort()
  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason({tag, _}) when is_atom(tag), do: Atom.to_string(tag)
  defp safe_reason(_), do: "execution_failed"
end
