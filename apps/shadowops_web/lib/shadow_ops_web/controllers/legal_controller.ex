defmodule ShadowOpsWeb.LegalController do
  use Phoenix.Controller, formats: [:json]

  alias ShadowOpsApi

  def index(conn, _params) do
    json(conn, ShadowOpsApi.legal())
  end
end
