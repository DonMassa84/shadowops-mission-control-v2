defmodule ShadowOpsWeb.LayersLive do
  use Phoenix.LiveView

  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsWeb.LayerEvaluator

  @refresh_ms 15_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_ms)
    {:ok, load(socket)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, load(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app_shell
      title="Layer Health"
      subtitle="Evidence-backed evaluation of ShadowOps operational layers"
      active="/layers"
      availability={@health.status}
      updated_at={@health.generated_at}
    >
      <section class="mc-hero" aria-labelledby="layer-health-title">
        <div class="mc-hero-copy">
          <div class="mc-hero-eyebrow">
            <.status_badge status={@health.status} />
            <span>Deterministic · read-only · no synthetic scores</span>
          </div>
          <h2 id="layer-health-title">Layer health at a glance</h2>
          <p>
            Missing evidence is reported as NOT_ASSESSED and excluded from the weighted overall score.
            Critical governance findings override a positive numeric score.
          </p>
          <div class="mc-hero-actions">
            <a class="mc-button is-primary" href="/">Mission Control</a>
            <a class="mc-button" href="/security">Security</a>
            <a class="mc-button" href="/audit">Audit</a>
            <a class="mc-button" href="/workflows">Workflows</a>
          </div>
        </div>
        <div class="mc-hero-stats" aria-label="Layer health summary">
          <div><span>Overall score</span><strong>{score(@health.score)}</strong><small>{@health.state}</small></div>
          <div><span>Assessed</span><strong>{@health.assessed_layers}/{@health.total_layers}</strong><small>{percent(@health.overall_coverage)} coverage</small></div>
          <div><span>Critical findings</span><strong>{@health.critical_findings}</strong><small>{@health.warnings} warnings</small></div>
        </div>
      </section>

      <section class="mc-grid" aria-label="Layer metrics">
        <.metric_card label="Overall" value={score(@health.score)} status={@health.status} source="LayerEvaluator" note={@health.state} />
        <.metric_card label="Assessed layers" value={"#{@health.assessed_layers}/#{@health.total_layers}"} status={if(@health.assessed_layers == @health.total_layers, do: "HEALTHY", else: "REVIEW")} source="evidence availability" />
        <.metric_card label="Coverage" value={percent(@health.overall_coverage)} status={coverage_state(@health.overall_coverage)} source="assessed / total layers" />
        <.metric_card label="Critical" value={@health.critical_findings} status={if(@health.critical_findings > 0, do: "CRITICAL", else: "HEALTHY")} source="rule-based findings" />
        <.metric_card label="Warnings" value={@health.warnings} status={if(@health.warnings > 0, do: "REVIEW", else: "HEALTHY")} source="rule-based findings" />
      </section>

      <.panel title="Operational ticker" description="Highest-priority layer states from the current evidence snapshot.">
        <div class="mc-source-meta">
          <span :for={layer <- ticker_layers(@health.layers)}>
            <strong>{layer.name}</strong> · {score(layer.score)} · <.status_badge status={layer.state} />
          </span>
        </div>
      </.panel>

      <.panel title="Layer health overview" description="Scores measure evidence quality and coverage, not raw data volume.">
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead>
              <tr><th>Layer</th><th>Score</th><th>State</th><th>Coverage</th><th>Warnings</th><th>Failures</th><th>Details</th></tr>
            </thead>
            <tbody>
              <tr :for={layer <- @health.layers}>
                <td><strong>{layer.name}</strong></td>
                <td>{score(layer.score)}</td>
                <td><.status_badge status={layer.state} /></td>
                <td>{percent(layer.coverage)}</td>
                <td>{layer.warnings}</td>
                <td>{layer.failures}</td>
                <td><a href={"/layers/#{layer.id}"}>Inspect</a></td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <.panel title="Top findings" description="Critical findings are ordered before warnings and informational evidence gaps.">
        <div :if={@health.findings == []} class="mc-unavailable" role="status">
          <div><.status_badge status="HEALTHY" /></div>
          <div><h2>No findings</h2><p>No rule-based findings were produced by the current evidence snapshot.</p></div>
        </div>
        <div :if={@health.findings != []} class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Severity</th><th>Layer</th><th>Code</th><th>Finding</th></tr></thead>
            <tbody>
              <tr :for={finding <- Enum.take(@health.findings, 20)}>
                <td><.status_badge status={finding.severity} /></td>
                <td><a href={"/layers/#{finding.layer_id}"}>{finding.layer_id}</a></td>
                <td>{finding.code}</td>
                <td>{finding.message}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>
    </.app_shell>
    """
  end

  defp load(socket), do: assign(socket, :health, LayerEvaluator.snapshot())

  defp ticker_layers(layers) do
    layers
    |> Enum.sort_by(fn layer -> {ticker_priority(layer.state), -(layer.score || -1)} end)
    |> Enum.take(8)
  end

  defp ticker_priority("CRITICAL"), do: 0
  defp ticker_priority("DEGRADED"), do: 1
  defp ticker_priority("REVIEW"), do: 2
  defp ticker_priority("NOT_ASSESSED"), do: 3
  defp ticker_priority(_state), do: 4

  defp score(nil), do: "N/A"
  defp score(value), do: "#{value}/100"

  defp percent(nil), do: "N/A"
  defp percent(value) when is_number(value), do: "#{round(value * 100)}%"

  defp coverage_state(nil), do: "NOT_ASSESSED"
  defp coverage_state(value) when value >= 0.85, do: "HEALTHY"
  defp coverage_state(value) when value >= 0.7, do: "REVIEW"
  defp coverage_state(_value), do: "DEGRADED"
end
