defmodule ShadowOpsWeb.LogsController do
  use Phoenix.Controller, formats: [:json]
  alias ShadowOpsApi

  def recent(conn, params), do: json(conn, ShadowOpsApi.logs(params))
end
