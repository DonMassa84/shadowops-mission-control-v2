defmodule ShadowOpsWeb.AIStatusController do
  use Phoenix.Controller, formats: [:json]

  alias ShadowOpsWeb.AIStatus

  def status(conn, _params), do: json(conn, AIStatus.snapshot())
  def models(conn, _params), do: json(conn, AIStatus.snapshot())
end
