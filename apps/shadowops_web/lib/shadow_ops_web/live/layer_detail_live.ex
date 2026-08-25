defmodule ShadowOpsWeb.LayerDetailLive do
  use Phoenix.LiveView

  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsWeb.LayerEvaluator

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case LayerEvaluator.layer(id) do
      {:ok, layer} ->
        {:ok, assign(socket, layer: layer)}

      {:error, :not_found} ->
        {:ok, socket |> put_flash(:error, "Unknown layer") |> redirect(to: "/layers")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app_shell
      title={@layer.name}
      subtitle="Layer health detail and evidence findings"
      active="/layers"
      availability={@layer.state}
      updated_at={@layer.updated_at}
    >
      <section class="mc-grid" aria-label="Layer detail metrics">
        <.metric_card label="Score" value={score(@layer.score)} status={@layer.state} source="LayerEvaluator" />
        <.metric_card label="Coverage" value={percent(@layer.coverage)} status={@layer.state} source="evidence coverage" />
        <.metric_card label="Warnings" value={@layer.warnings} status={if(@layer.warnings > 0, do: "REVIEW", else: "HEALTHY")} source="rule-based findings" />
        <.metric_card label="Failures" value={@layer.failures} status={if(@layer.failures > 0, do: "CRITICAL", else: "HEALTHY")} source="rule-based findings" />
      </section>

      <.panel title="Measured evidence" description="Only aggregate, privacy-safe evidence used by this layer score.">
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Metric</th><th>Observed</th></tr></thead>
            <tbody>
              <tr :for={{key, value} <- Enum.sort_by(@layer.metrics, fn {key, _value} -> to_string(key) end)}>
                <td><strong>{humanize(key)}</strong></td>
                <td>{display(value)}</td>
              </tr>
              <tr :if={map_size(@layer.metrics) == 0}><td colspan="2">No measurable aggregate metrics are available.</td></tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <.panel title="Findings" description="Deterministic checks explain why the layer has its current state.">
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Severity</th><th>Code</th><th>Finding</th></tr></thead>
            <tbody>
              <tr :for={finding <- @layer.findings}>
                <td><.status_badge status={finding.severity} /></td>
                <td>{finding.code}</td>
                <td>{finding.message}</td>
              </tr>
              <tr :if={@layer.findings == []}><td colspan="3">No findings for this layer.</td></tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <div class="mc-hero-actions"><a class="mc-button is-primary" href="/layers">Back to Layer Health</a></div>
    </.app_shell>
    """
  end

  defp score(nil), do: "N/A"
  defp score(value), do: "#{value}/100"
  defp percent(nil), do: "N/A"
  defp percent(value) when is_number(value), do: "#{round(value * 100)}%"
  defp display(nil), do: "N/A"
  defp display(value) when is_boolean(value), do: to_string(value)
  defp display(value) when is_map(value), do: Jason.encode!(value)
  defp display(value) when is_list(value), do: Enum.map_join(value, ", ", &to_string/1)
  defp display(value), do: to_string(value)

  defp humanize(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
