defmodule ShadowOpsWeb.FacebookBalanceController do
  use Phoenix.Controller, formats: [:json]

  def index(conn, _params), do: json(conn, ShadowOpsApi.facebook_balance())
end
