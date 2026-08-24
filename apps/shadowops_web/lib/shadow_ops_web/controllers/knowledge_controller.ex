defmodule ShadowOpsWeb.KnowledgeController do
  use Phoenix.Controller, formats: [:json]
  def index(conn, _), do: json(conn, ShadowOpsApi.knowledge())
end
