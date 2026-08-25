defmodule ShadowOpsWeb.ServicesLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi
  alias ShadowOpsCore.ExecutionTracker
  alias ShadowOpsWeb.Plugs.Security

  def mount(_params, _session, socket) do
    data = ShadowOpsApi.services()
    filters = %{"scope" => "", "state" => "", "source" => ""}
    {:ok, assign(socket, data: data, services: data.services, filters: filters, last_run: nil)}
  end

  def handle_event("filter", params, socket) do
    filters =
      Map.merge(socket.assigns.filters, Map.take(params, Map.keys(socket.assigns.filters)))

    rows =
      Enum.filter(socket.assigns.data.services, fn row ->
        matches_filter?(row.scope, filters["scope"]) and
          matches_filter?(row.active_state, filters["state"]) and
          matches_filter?(row.source, filters["source"])
      end)

    {:noreply, assign(socket, filters: filters, services: rows)}
  end

  def handle_event("operate", params, socket) do
    actor = params["actor"] || ""
    token = params["write_token"] || ""
    service_id = params["service_id"] || ""
    action = params["action"] || ""
    approval_id = blank_to_nil(params["approval_id"])

    with :ok <- Security.authorize_live_write(actor, token),
         true <- action in ["start", "restart", "stop"] || {:error, :invalid_action},
         {:ok, _service, run} <-
           ExecutionTracker.execute_service(action, actor, service_id, %{
             approval_id: approval_id,
             trigger: "mission_control_ui"
           }) do
      data = ShadowOpsApi.services()

      {:noreply,
       socket
       |> assign(data: data, services: data.services, last_run: run)
       |> put_flash(:info, "#{service_id}: #{action} completed · #{run.evaluation.verdict} #{run.score}/100")}
    else
      {:error, reason, run} ->
        {:noreply,
         socket
         |> assign(last_run: run)
         |> put_flash(:error, "Service action blocked/failed: #{safe_reason(reason)}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Service action unavailable: #{safe_reason(reason)}")}

      false ->
        {:noreply, put_flash(socket, :error, "Invalid service action")}
    end
  end

  def render(assigns) do
    ~H"""
    <.app_shell title="Services" subtitle="Governed local runtime control and evaluation" active="/services" availability={@data.availability} updated_at={@data.updated_at}>
      <.source_meta source={@data.source} updated_at={@data.updated_at} availability={@data.availability} />

      <.panel title="Governed service control" description="Credentials are validated per action and are never stored in LiveView assigns. L2 operations still require a valid approval when policy demands it.">
        <form id="service-control" class="mc-filter" phx-submit="operate" autocomplete="off">
          <label>Service<select name="service_id" required><option :for={row <- @data.services} value={service_id(row)}>{row.name}</option></select></label>
          <label>Action<select name="action" required><option value="start">Start</option><option value="restart">Restart</option><option value="stop">Stop</option></select></label>
          <label>Actor<input name="actor" required maxlength="120" placeholder="operator" /></label>
          <label>Write token<input type="password" name="write_token" required autocomplete="off" /></label>
          <label>Approval ID<input name="approval_id" placeholder="required for L2 when policy demands" /></label>
          <button class="mc-button" type="submit">Execute service action</button>
        </form>
        <p :if={@last_run} class="mc-callout">
          Last run: <a href={"/runs/#{@last_run.id}"} class="mc-mono">{@last_run.id}</a>
          · <strong>{@last_run.status}</strong>
          · score {@last_run.score || "—"}/100
        </p>
      </.panel>

      <.panel title="Service records" description="Runtime state is refreshed after governed actions; no arbitrary shell control is exposed.">
        <form id="service-filters" class="mc-filter" phx-change="filter"><label>Scope<select name="scope"><option value="">All</option><option :for={v <- values(@data.services, :scope)} value={v}>{v}</option></select></label><label>State<select name="state"><option value="">All</option><option :for={v <- values(@data.services, :active_state)} value={v}>{v}</option></select></label><label>Source<select name="source"><option value="">All</option><option :for={v <- values(@data.services, :source)} value={v}>{v}</option></select></label></form>
        <div :if={@services != []} class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Name</th><th>Scope</th><th>Active</th><th>Sub-state</th><th>Enabled</th><th>PID</th><th>Uptime</th><th>Restarts</th><th>Last error</th><th>Source</th></tr></thead><tbody><tr :for={row <- @services}><td class="mc-mono">{row.name}</td><td>{row.scope}</td><td><.status_badge status={row.active_state} /></td><td>{row.sub_state}</td><td>{row.enabled || "Not measured"}</td><td>{row.pid || "—"}</td><td>{row.uptime_seconds || "—"}</td><td>{row.restart_count || "Not measured"}</td><td>{inspect(row.last_error)}</td><td>{row.source}</td></tr></tbody></table></div><p :if={@services == []} class="mc-empty">No service records match the current filters.</p>
      </.panel>
    </.app_shell>
    """
  end

  defp service_id(row), do: row.scope <> ":" <> row.name
  defp matches_filter?(_value, ""), do: true
  defp matches_filter?(value, filter), do: value == filter
  defp values(rows, key), do: rows |> Enum.map(&Map.fetch!(&1, key)) |> Enum.uniq() |> Enum.sort()
  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason({tag, _}) when is_atom(tag), do: Atom.to_string(tag)
  defp safe_reason(_), do: "execution_failed"
end
