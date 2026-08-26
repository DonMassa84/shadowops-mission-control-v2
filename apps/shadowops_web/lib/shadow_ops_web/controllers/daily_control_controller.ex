defmodule ShadowOpsWeb.DailyControlController do
  @moduledoc """
  Read-only Daily Control API endpoint.

  GET /api/daily-control returns the canonical shadowops.daily_control snapshot.
  Performs a single aggregated source fetch, then projects purely through
  ShadowOpsCore.DailyControl. No runtime mutation, no external action.
  """
  use Phoenix.Controller, formats: [:json]

  alias ShadowOpsCore.RuntimeSources
  alias ShadowOpsCore.ApprovalStore
  alias ShadowOpsCore.RunStore
  alias ShadowOpsWeb.SecurityStatus
  alias ShadowOpsWeb.ProjectDomains

  def show(conn, _params) do
    overview = %{
      system: RuntimeSources.system(),
      security: SecurityStatus.check(),
      services: RuntimeSources.services(),
      backups: RuntimeSources.backups(),
      approvals: ApprovalStore.list(),
      runs: RunStore.list(),
      career: RuntimeSources.career(),
      evidence: RuntimeSources.evidence()
    }

    ihk_domain = ProjectDomains.snapshot(:ihk)

    snapshot = ShadowOpsCore.DailyControl.build(overview, ihk_domain)
    json(conn, snapshot)
  end
end
