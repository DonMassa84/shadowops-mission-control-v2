defmodule ShadowOpsWeb.SecurityController do
  use Phoenix.Controller, formats: [:json]

  def status(conn, _params) do
    json(conn, ShadowOpsWeb.SecurityStatus.check())
  end
end
