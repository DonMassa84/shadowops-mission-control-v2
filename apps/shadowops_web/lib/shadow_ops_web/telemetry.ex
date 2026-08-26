defmodule ShadowOpsWeb.Telemetry do
  @moduledoc """
  Canonical Phoenix/BEAM metrics exposed through the loopback-only LiveDashboard.

  Metrics are aggregate operational telemetry only; no prompts, message bodies, actor identifiers,
  or other private payloads are included.
  """

  import Telemetry.Metrics

  def metrics do
    [
      summary("phoenix.endpoint.stop.duration", unit: {:native, :millisecond}),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration", unit: {:native, :millisecond}),
      summary("phoenix.channel_joined.duration", unit: {:native, :millisecond}),
      counter("shadowops.workflow.run.count", tags: [:status]),
      summary("shadowops.workflow.run.duration", unit: {:native, :millisecond}),
      counter("shadowops.node.action.count", tags: [:status]),
      counter("shadowops.governance.decision.count", tags: [:status])
    ]
  end
end
