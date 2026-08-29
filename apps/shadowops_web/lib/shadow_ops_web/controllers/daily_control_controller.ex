defmodule ShadowOpsWeb.DailyControlController do
  @moduledoc """
  Read-only Daily Control API endpoint.

  GET /api/daily-control returns the canonical shadowops.daily_control snapshot.
  It performs a single aggregated overview fetch plus a single IHK domain
  snapshot, then projects purely through ShadowOpsCore.DailyControl. No
  runtime mutation, no external action.
  """
  use Phoenix.Controller, formats: [:json]
  alias ShadowOpsWeb.RuntimeOverview
  alias ShadowOpsWeb.ProjectDomains

  def show(conn, _params) do
    snapshot =
      ShadowOpsCore.DailyControl.snapshot(
        overview: RuntimeOverview.snapshot(),
        ihk_domain: ProjectDomains.snapshot(:ihk)
      )

    json(conn, snapshot)
  end
end
