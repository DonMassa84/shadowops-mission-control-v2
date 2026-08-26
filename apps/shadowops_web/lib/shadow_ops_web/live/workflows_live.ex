defmodule ShadowOpsWeb.WorkflowsLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi
  alias ShadowOpsWeb.OneClick
  alias WorkflowEngine.{Inventory, Registry}

  def mount(_params, _session, socket) do
    {:ok, canonical} = ShadowOpsApi.list_workflows()
    {:ok, registry} = Registry.load()

    inventory = Inventory.summary(registry)
    workflows = (canonical ++ Inventory.external_workflows(registry)) |> Enum.sort_by(& &1["id"])

    filters = %{
      "search" => "",
      "category" => "",
      "domain" => "",
      "status" => "",
      "runtime" => "",
      "sort" => "id"
    }

    {:ok,
     assign(socket,
       workflows: workflows,
       visible: workflows,
       inventory: inventory,
       filters: filters,
       one_click_ready: OneClick.available?(),
       updated_at: now()
     )}
  end

  def handle_event("filter", params, socket) do
    filters =
      Map.merge(socket.assigns.filters, Map.take(params, Map.keys(socket.assigns.filters)))

    {:noreply,
     assign(socket, filters: filters, visible: filter(socket.assigns.workflows, filters))}
  end

  def handle_event("clear", _params, socket) do
    filters =
      Map.new(socket.assigns.filters, fn {key, _} ->
        {key, if(key == "sort", do: "id", else: "")}
      end)

    {:noreply,
     assign(socket, filters: filters, visible: filter(socket.assigns.workflows, filters))}
  end

  def handle_event("one_click_run", %{"id" => id}, socket) do
    case OneClick.execute_workflow(id) do
      {:ok, run} ->
        {:noreply,
         socket
         |> refresh_inventory()
         |> put_flash(:info, "#{id}: one-click execution accepted · #{run.status}")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "#{id}: one-click execution blocked · #{safe_reason(reason)}")}
    end
  end

  def render(assigns) do
    ~H"""
    <.app_shell title="Workflows" subtitle="Canonical + external runtime inventory" active="/workflows" updated_at={@updated_at}>
      <.source_meta source="workflow_registry_v2.yaml" updated_at={@updated_at} availability="AVAILABLE" />

      <section class="mc-grid" aria-label="Workflow inventory metrics">
        <.metric_card label="Total workflow slots" value={@inventory["total_count"]} status="AVAILABLE" source="registry v2 + external runtime sets" />
        <.metric_card label="Canonical" value={@inventory["canonical_count"]} status="AVAILABLE" source="workflows map" />
        <.metric_card label="External" value={@inventory["external_count"]} status="AVAILABLE" source="external_runtime_sets" />
        <.metric_card label="Named in source" value={@inventory["named_count"]} status="AVAILABLE" source="explicit workflow IDs only" />
        <.metric_card label="IDs not imported" value={@inventory["unresolved_count"]} status={if(@inventory["unresolved_count"] > 0, do: "DEGRADED", else: "AVAILABLE")} source="source counts without individual IDs" />
      </section>

      <p class="mc-callout">
        One-click mode: <strong>{if(@one_click_ready, do: "READY", else: "WRITE TOKEN REQUIRED")}</strong> · a click is the explicit operator decision; L2 approvals are persisted before execution.
      </p>

      <.panel title="External runtime coverage" description="Counts are source-backed. Included domain packs are not double-counted; missing IDs remain unresolved instead of being invented.">
        <div class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Runtime set</th><th>Workflows</th><th>Named</th><th>IDs pending import</th><th>Counted in total</th><th>Runtime</th><th>Relationship</th></tr></thead><tbody>
          <tr :for={set <- @inventory["sets"]}>
            <td class="mc-mono">{set["id"]}</td>
            <td>{set["workflow_count"]}</td>
            <td>{set["named_workflow_count"]}</td>
            <td>{set["unresolved_count"]}</td>
            <td>{if(set["counted_in_total"], do: "yes", else: "included in parent")}</td>
            <td class="mc-mono">{available(set["runtime"])}</td>
            <td>{available(set["relationship"])}</td>
          </tr>
        </tbody></table></div>
      </.panel>

      <.panel title="Named workflows" description="Executable canonical rows run directly from this table. External registry-only rows remain read-only until a real runtime adapter exists.">
        <form id="workflow-filters" class="mc-filter" phx-change="filter" phx-submit="filter">
          <label>Search<input name="search" value={@filters["search"]} placeholder="ID or name" /></label>
          <label>Category<select name="category"><option value="">All</option><option :for={v <- values(@workflows, "type")} value={v} selected={@filters["category"] == v}>{v}</option></select></label>
          <label>Domain / set<select name="domain"><option value="">All</option><option :for={v <- values(@workflows, "domain")} value={v} selected={@filters["domain"] == v}>{v}</option></select></label>
          <label>Status<select name="status"><option value="">All</option><option :for={v <- values(@workflows, "status")} value={v} selected={@filters["status"] == v}>{v}</option></select></label>
          <label>Runtime<select name="runtime"><option value="">All</option><option :for={v <- values(@workflows, "runtime")} value={v} selected={@filters["runtime"] == v}>{v}</option></select></label>
          <label>Sort<select name="sort"><option value="id">ID</option><option value="domain" selected={@filters["sort"] == "domain"}>Domain</option><option value="status" selected={@filters["sort"] == "status"}>Status</option></select></label>
          <button class="mc-button" type="button" phx-click="clear">Clear filters</button>
        </form>
        <div class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Workflow</th><th>Category</th><th>Domain / set</th><th>Status</th><th>Runtime</th><th>Risk</th><th>Last run</th><th>Approval</th><th>One click</th></tr></thead><tbody>
          <tr :for={w <- @visible}>
            <td>
              <a :if={canonical?(w)} href={"/workflows/#{w["id"]}"}><strong>{display_name(w)}</strong><br/><span class="mc-mono mc-muted">{w["id"]}</span></a>
              <span :if={!canonical?(w)}><strong>{display_name(w)}</strong><br/><span class="mc-mono mc-muted">{w["id"]}</span></span>
            </td>
            <td>{available(w["type"])}</td>
            <td>{available(w["domain"])}</td>
            <td><.status_badge status={w["execution_status"]} /></td>
            <td class="mc-mono">{available(w["target_runtime"] || w["runtime"])}</td>
            <td>{available(w["risk_level"])}</td>
            <td>{last_run(w["last_run"])}</td>
            <td><.status_badge status={approval_status(w)} label={approval_label(w)} /></td>
            <td>
              <button
                :if={workflow_runnable?(w)}
                class="mc-button"
                type="button"
                phx-click="one_click_run"
                phx-value-id={w["id"]}
                disabled={!@one_click_ready}
                title={if(@one_click_ready, do: "Approve if required and run now", else: "Configure SHADOWOPS_WRITE_TOKEN")}
              >
                ✓ Approve & run
              </button>
              <a :if={canonical?(w) and !workflow_runnable?(w)} class="mc-button" href={"/workflows/#{w["id"]}"}>Review</a>
              <a :if={!canonical?(w)} class="mc-button" href="/integrations">Open source</a>
            </td>
          </tr>
        </tbody></table></div>
        <p :if={@visible == []} class="mc-empty">No workflows match the current filters.</p>
      </.panel>
    </.app_shell>
    """
  end

  defp refresh_inventory(socket) do
    {:ok, canonical} = ShadowOpsApi.list_workflows()
    {:ok, registry} = Registry.load()
    workflows = (canonical ++ Inventory.external_workflows(registry)) |> Enum.sort_by(& &1["id"])

    assign(socket,
      workflows: workflows,
      visible: filter(workflows, socket.assigns.filters),
      inventory: Inventory.summary(registry),
      one_click_ready: OneClick.available?(),
      updated_at: now()
    )
  end

  defp filter(rows, f) do
    rows
    |> Enum.filter(fn w ->
      search = String.downcase(f["search"] || "")

      (search == "" or
         String.contains?(String.downcase(w["id"] <> " " <> display_name(w)), search)) and
        match_field(w, "type", f["category"]) and match_field(w, "domain", f["domain"]) and
        match_field(w, "status", f["status"]) and match_field(w, "runtime", f["runtime"])
    end)
    |> Enum.sort_by(&to_string(&1[f["sort"]] || &1["id"]))
  end

  defp match_field(_w, _key, ""), do: true
  defp match_field(w, "runtime", value), do: (w["target_runtime"] || w["runtime"]) == value
  defp match_field(w, key, value), do: w[key] == value

  defp values(rows, "runtime"),
    do: rows |> Enum.map(&(&1["target_runtime"] || &1["runtime"])) |> compact()

  defp values(rows, key), do: rows |> Enum.map(& &1[key]) |> compact()

  defp compact(values),
    do: values |> Enum.filter(&(is_binary(&1) and &1 != "")) |> Enum.uniq() |> Enum.sort()

  defp canonical?(w), do: w["source_kind"] != "external_runtime_set"

  defp workflow_runnable?(w) do
    status = w["execution_status"] || w["status"] || "UNAVAILABLE"

    canonical?(w) and w["executable"] != false and
      status not in ["UNAVAILABLE", "DISABLED", "DISABLED_BY_CONFIGURATION", "NOT_CONNECTED"]
  end

  defp approval_status(%{"source_kind" => "external_runtime_set", "approval_required" => true}),
    do: "REVIEW"

  defp approval_status(%{"source_kind" => "external_runtime_set", "approval_required" => false}),
    do: "READY"

  defp approval_status(%{"source_kind" => "external_runtime_set"}), do: "UNAVAILABLE"
  defp approval_status(_), do: "REVIEW"

  defp approval_label(%{"source_kind" => "external_runtime_set", "approval_required" => true}),
    do: "source approval required"

  defp approval_label(%{"source_kind" => "external_runtime_set", "approval_required" => false}),
    do: "no source approval"

  defp approval_label(%{"source_kind" => "external_runtime_set"}), do: "not specified"
  defp approval_label(_), do: "L2 approval"

  defp display_name(w),
    do:
      w["display_name"] || w["name"] || w["id"] |> String.replace("_", " ") |> String.capitalize()

  defp available(nil), do: "Not available from current source"
  defp available(""), do: "Not available from current source"
  defp available(value), do: to_string(value)
  defp last_run(nil), do: "Not available from current source"
  defp last_run(run), do: "#{run.status} / #{run.finished_at || run.started_at || run.queued_at}"
  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason({tag, _}) when is_atom(tag), do: Atom.to_string(tag)
  defp safe_reason(_), do: "execution_failed"
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
