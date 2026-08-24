defmodule ShadowOpsWeb.ProjectDomainsLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsWeb.ProjectDomains

  def mount(_params, _session, socket), do: {:ok, assign(socket, domains: ProjectDomains.all())}

  def render(assigns) do
    ~H"""
    <.app_shell title="Project domains" subtitle="Private local domain registry" active="/projects" availability={overall(@domains)}>
      <section class="mc-grid" aria-label="Project domain overview">
        <.metric_card
          :for={domain <- @domains}
          label={domain.name}
          value={domain.status}
          status={domain.status}
          source={domain.source_type}
          note={domain.summary}
        />
      </section>

      <.panel title="Connected domains" description="Missing local manifests remain NOT_CONFIGURED. Raw records are never rendered from this registry.">
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Domain</th><th>Status</th><th>Open items</th><th>Next deadline</th><th>Source</th><th>Action</th></tr></thead>
            <tbody>
              <tr :for={domain <- @domains}>
                <td><strong>{domain.name}</strong></td>
                <td><.status_badge status={domain.status} /></td>
                <td>{domain.open_items || "Not evidenced"}</td>
                <td>{domain.next_deadline || "Not evidenced"}</td>
                <td class="mc-mono">{domain.source || "Not configured"}</td>
                <td><a class="mc-button" href={"/projects/#{domain.id}"}>Open</a></td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>
    </.app_shell>
    """
  end

  defp overall(domains) do
    cond do
      Enum.any?(domains, &(&1.status in ["FAILED", "ERROR"])) -> "DEGRADED"
      Enum.any?(domains, &(&1.status == "READY")) -> "READY"
      true -> "NOT_CONFIGURED"
    end
  end
end
