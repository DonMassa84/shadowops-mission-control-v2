defmodule ShadowOpsWeb.ProjectCatalogController do
  use Phoenix.Controller, formats: [:json]

  alias ShadowOpsWeb.ProjectCatalog

  def index(conn, _params) do
    json(conn, ProjectCatalog.snapshot())
  end
end
