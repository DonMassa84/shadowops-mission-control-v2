defmodule ShadowOpsWeb.AgentsController do
  use Phoenix.Controller, formats: [:json]
  alias ShadowOpsApi

  def index(conn, _params), do: json(conn, ShadowOpsApi.agents())
end
