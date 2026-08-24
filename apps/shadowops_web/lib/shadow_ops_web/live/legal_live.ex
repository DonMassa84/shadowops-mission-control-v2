defmodule ShadowOpsWeb.LegalLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents

  def mount(_params, _session, socket) do
    {:ok, assign(socket, data: ShadowOpsWeb.LegalRegistry.snapshot())}
  end

  def render(assigns) do
    ~H"""
    <.app_shell
      title="Legal / Evidence"
      subtitle="Redacted legal case metadata with fail-closed private evidence boundaries"
      active="/legal"
      availability={@data.availability}
      updated_at={@data.updated_at}
    >
      <.source_meta
        source={@data.source}
        updated_at={@data.updated_at}
        availability={@data.availability}
      />

      <div class="mc-metrics">
        <.metric_card
          label="Cases"
          value={@data.record_count}
          status={@data.status}
          source={@data.source}
          note="Redacted metadata only"
        />
        <.metric_card
          label="Classification"
          value={@data.privacy.classification}
          status="REVIEW"
          note="Original evidence remains local/private"
        />
        <.metric_card
          label="Private store"
          value={if Map.get(@data.privacy, :local_private_store_required, true), do: "Required", else: "Unknown"}
          status="READY"
          note="No bank data or full correspondence exposed"
        />
      </div>

      <.panel
        title="Legal cases"
        description="Operational status only. Sensitive source files are deliberately excluded from this interface and Git."
      >
        <div :if={@data.records != []} class="mc-table-wrap">
          <table class="mc-table">
            <thead>
              <tr>
                <th>Case</th>
                <th>Type</th>
                <th>Status</th>
                <th>Reference</th>
                <th>Key state</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={case <- @data.records}>
                <td>{case["id"]}</td>
                <td>{case["type"]}</td>
                <td><.status_badge status={case["status"] || "UNKNOWN"} /></td>
                <td>{case["reference"] || case["hearing_date"] || "—"}</td>
                <td>{case_summary(case)}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={@data.records == []} class="mc-empty">No redacted legal case metadata is available.</p>
      </.panel>

      <.panel
        title="Privacy boundary"
        description="Zero-Trust rule: public/control-plane metadata and private legal evidence remain separate."
      >
        <ul>
          <li>Bank data: excluded</li>
          <li>Payment proofs: excluded</li>
          <li>Full lawyer correspondence: excluded</li>
          <li>Original case files / USB evidence: excluded</li>
          <li>Audit and approval workflows may reference case IDs, never raw secrets.</li>
        </ul>
      </.panel>
    </.app_shell>
    """
  end

  defp case_summary(case) do
    cond do
      is_number(case["remaining_amount_at_reference_date_eur"]) ->
        "Remaining amount #{case["remaining_amount_at_reference_date_eur"]} EUR"

      is_binary(case["hearing_date"]) ->
        "Hearing #{case["hearing_date"]} #{case["hearing_time"] || ""}"

      true ->
        "Redacted operational metadata"
    end
  end
end
