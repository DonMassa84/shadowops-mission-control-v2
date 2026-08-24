defmodule ShadowOpsWeb.IntegrationsController do
  use Phoenix.Controller, formats: [:json]

  alias ShadowOpsWeb.IntegrationCatalog

  def index(conn, _params), do: json(conn, IntegrationCatalog.snapshot())
end
