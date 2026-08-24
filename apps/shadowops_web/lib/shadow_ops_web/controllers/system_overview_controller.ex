defmodule ShadowOpsWeb.SystemOverviewController do
  use Phoenix.Controller, formats: [:json]

  alias ShadowOpsWeb.RuntimeOverview

  def show(conn, _params), do: json(conn, RuntimeOverview.snapshot())
end
