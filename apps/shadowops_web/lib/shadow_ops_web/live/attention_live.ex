defmodule ShadowOpsWeb.AttentionLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsWeb.{RuntimeOverview, SourceRegistry, IntegrationCatalog}

  def mount(_params, _session, socket) do
    {:ok, load(socket)}
  end

  def render(assigns) do
    ~H"""
    <.app_shell
      title="Attention Required"
      subtitle="All items that need operator action or investigation"
      active="/attention"
      availability={@overall_availability}
    >
      <.panel title="Attention Required" description="Exceptions, blockers, and degraded states across all domains.">
        <div :if={@attention_items == []} class="mc-empty">
          <p>No attention items at this time. All monitored domains are within acceptable parameters.</p>
        </div>

        <section :if={@attention_items != []} class="mc-grid" aria-label="Attention items">
          <.unavailable_state
            :for={item <- @attention_items}
            title={item.title}
            state={item.state}
            reason={item.reason}
            source={item.source}
            evidence={item.evidence}
            unlock_requirements={item.unlock_requirements}
          />
        </section>
      </.panel>

      <.panel title="Degraded Capabilities" description="Capabilities that are partially available but require attention.">
        <section class="mc-grid" aria-label="Degraded capabilities">
          <.capability_card
            :for={cap <- @degraded_capabilities}
            title={cap.name}
            state={cap.state}
            mode={cap.mode}
            real_data={cap.real_data}
            reachable={cap.reachable}
            synthetic={cap.synthetic}
            runtime={cap.runtime}
            approval={cap.approval}
            evidence={cap.evidence}
            last_probe={cap.last_probe}
            unlock_requirement={cap.unlock_requirement}
          />
        </section>
      </.panel>
    </.app_shell>
    """
  end

  defp load(socket) do
    overview = RuntimeOverview.snapshot()
    integrations = IntegrationCatalog.snapshot()
    sources = SourceRegistry.all()

    attention_items = build_attention_items(overview, integrations, sources)
    degraded_capabilities = build_degraded_capabilities(integrations, sources)
    overall_availability = calculate_overall_availability(attention_items)

    assign(socket,
      attention_items: attention_items,
      degraded_capabilities: degraded_capabilities,
      overall_availability: overall_availability,
      updated_at: now()
    )
  end

  defp build_attention_items(overview, _integrations, sources) do
    items = []

    # Check core systems
    items =
      if overview.security.overall in ["DEGRADED", "FAIL", "ERROR"] do
        [
          %{
            title: "Security",
            state: "DEGRADED",
            reason: overview.security.overall,
            source: overview.security.source,
            evidence: [],
            unlock_requirements: ["Review security status page"]
          }
          | items
        ]
      else
        items
      end

    items =
      if overview.audit.state in ["DEGRADED", "FAIL", "ERROR"] do
        [
          %{
            title: "Audit",
            state: "DEGRADED",
            reason: overview.audit.state,
            source: overview.audit.source,
            evidence: [],
            unlock_requirements: ["Verify audit chain"]
          }
          | items
        ]
      else
        items
      end

    items =
      if overview.backups.status in ["DEGRADED", "FAIL", "ERROR"] do
        [
          %{
            title: "Backups",
            state: "DEGRADED",
            reason: overview.backups.error_message || overview.backups.status,
            source: overview.backups.source,
            evidence: [],
            unlock_requirements: ["Check backup integrity"]
          }
          | items
        ]
      else
        items
      end

    # Check connectors
    items =
      Enum.reduce(Map.get(overview.connectors, :records, []), items, fn connector, acc ->
        if Map.get(connector, :status) in ["DEGRADED", "FAILED", "ERROR", "UNAVAILABLE"] do
          [
            %{
              title: connector.name || connector.id,
              state: Map.get(connector, :status),
              reason: connector.error_message || "No evidence",
              source: connector.source || "unknown",
              evidence: [],
              unlock_requirements: [
                "Verify connector configuration",
                "Check OAuth tokens",
                "Validate API reachability"
              ]
            }
            | acc
          ]
        else
          acc
        end
      end)

    # Check imports
    items =
      Enum.reduce(sources, items, fn source, acc ->
        if source.status in ["NOT_CONFIGURED", "UNAVAILABLE"] do
          [
            %{
              title: source.name,
              state: source.status,
              reason: source.error_message || "No import evidence",
              source: source.source,
              evidence: [],
              unlock_requirements: [
                "Add import evidence file",
                "Configure OAuth secrets",
                "Run connector sync"
              ]
            }
            | acc
          ]
        else
          acc
        end
      end)

    # Check approvals pending
    pending = Enum.count(Map.get(overview.approvals, :records, []), &(&1.status == "PENDING"))

    items =
      if pending > 0 do
        [
          %{
            title: "Approvals",
            state: "DEGRADED",
            reason: "#{pending} pending approval(s)",
            source: overview.approvals.source,
            evidence: [],
            unlock_requirements: ["Review and approve/reject pending items"]
          }
          | items
        ]
      else
        items
      end

    Enum.reverse(items)
  end

  defp build_degraded_capabilities(integrations, sources) do
    caps = []

    caps =
      Enum.reduce(integrations.records, caps, fn record, acc ->
        if record.status in ["DEGRADED", "PARTIAL", "CONFIGURATION_REQUIRED", "APPROVAL_REQUIRED"] do
          [
            %{
              name: record.name,
              state: record.status,
              mode: record.scope,
              real_data: record.real_data,
              reachable: record.reachable,
              synthetic: record.synthetic,
              runtime: record.kind,
              approval: record.secret_binding?.state,
              evidence: record.error_message || record.source,
              last_probe: record.last_sync,
              unlock_requirement: record.error_message || "Verify configuration and evidence"
            }
            | acc
          ]
        else
          acc
        end
      end)

    caps =
      Enum.reduce(sources, caps, fn source, acc ->
        if source.status in ["NOT_CONFIGURED", "DEGRADED", "PARTIAL"] do
          [
            %{
              name: source.name,
              state: source.status,
              mode: "import",
              real_data: source.real_data,
              reachable: source.reachable,
              synthetic: source.synthetic,
              runtime: source.adapter,
              approval: source.secret_binding.state,
              evidence: source.error_message,
              last_probe: source.last_sync,
              unlock_requirement: source.error_message || "Configure OAuth and import evidence"
            }
            | acc
          ]
        else
          acc
        end
      end)

    Enum.reverse(caps)
  end

  defp calculate_overall_availability(items) do
    cond do
      Enum.any?(items, &(&1.state in ["FAIL", "ERROR", "UNAVAILABLE"])) -> "DEGRADED"
      Enum.any?(items, &(&1.state in ["DEGRADED"])) -> "DEGRADED"
      true -> "AVAILABLE"
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
