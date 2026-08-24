defmodule ShadowOpsWeb.AIStatusController do
  use Phoenix.Controller, formats: [:json]

  alias ShadowOpsApi

  def status(conn, _params) do
    json(conn, ShadowOpsApi.ai())
  end

  def models(conn, _params) do
    json(conn, ShadowOpsApi.ai())
  end
end
