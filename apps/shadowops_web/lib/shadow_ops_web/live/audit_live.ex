defmodule ShadowOpsWeb.AuditLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsCore.Audit

  def mount(_params, _session, socket) do
    filters = %{"actor" => "", "action" => "", "result" => "", "date" => ""}
    {:ok, socket |> assign(filters: filters) |> load()}
  end

  def handle_event("verify", _params, socket), do: {:noreply, load(socket)}

  def handle_event("filter", params, socket) do
    filters =
      Map.merge(socket.assigns.filters, Map.take(params, Map.keys(socket.assigns.filters)))

    {:noreply,
     assign(socket, filters: filters, events: filter(socket.assigns.all_events, filters))}
  end

  def render(assigns) do
    ~H"""
    <.app_shell title="Audit" subtitle="Append-only governance journal" active="/audit" availability={@state} updated_at={@updated_at}>
      <.panel title="Hash chain" description="Verification recomputes every linked entry.">
        <:actions><button class="mc-button" phx-click="verify">Verify chain</button></:actions>
        <div class="mc-statline"><.status_badge status={@state} /><span>{@entries} verified entries</span><span class="mc-muted">Source: append-only audit JSONL</span></div>
      </.panel>
      <.panel title="Recent events">
        <form id="audit-filters" class="mc-filter" phx-change="filter" phx-submit="filter">
          <label>Actor<input name="actor" value={@filters["actor"]} /></label>
          <label>Action<select name="action"><option value="">All</option><option :for={value <- values(@all_events, "action")} value={value}>{value}</option></select></label>
          <label>Result<select name="result"><option value="">All</option><option :for={value <- values(@all_events, "result")} value={value}>{value}</option></select></label>
          <label>Date<input type="date" name="date" value={@filters["date"]} /></label>
        </form>
        <div :if={@events != []} class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Timestamp</th><th>Actor</th><th>Action</th><th>Resource</th><th>Result</th><th>Evidence</th><th>Chain</th></tr></thead><tbody><tr :for={e <- @events}><td>{e["timestamp"]}</td><td>{e["actor"]}</td><td>{e["action"]}</td><td>{e["resource"]}</td><td><.status_badge status={e["result"]} /></td><td>{e["evidence_ref"] || "Not available"}</td><td><.status_badge status={@state} /></td></tr></tbody></table></div>
        <p :if={@events == []} class="mc-empty">No audit event matches the current filters.</p>
      </.panel>
    </.app_shell>
    """
  end

  defp load(socket) do
    {state, entries} =
      case Audit.verify() do
        {:ok, result} -> {"VALID", result.entries}
        {:error, _} -> {"INVALID", 0}
      end

    all_events = Audit.list()

    assign(socket,
      all_events: all_events,
      events: filter(all_events, socket.assigns.filters),
      state: state,
      entries: entries,
      updated_at: now()
    )
  end

  defp filter(events, filters) do
    Enum.filter(events, fn event ->
      contains?(event["actor"], filters["actor"]) and equals?(event["action"], filters["action"]) and
        equals?(event["result"], filters["result"]) and
        date_matches?(event["timestamp"], filters["date"])
    end)
  end

  defp contains?(_value, ""), do: true

  defp contains?(value, filter),
    do: String.contains?(String.downcase(value || ""), String.downcase(filter))

  defp equals?(_value, ""), do: true
  defp equals?(value, filter), do: value == filter
  defp date_matches?(_value, ""), do: true
  defp date_matches?(value, date), do: String.starts_with?(value || "", date)

  defp values(events, key),
    do: events |> Enum.map(& &1[key]) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
