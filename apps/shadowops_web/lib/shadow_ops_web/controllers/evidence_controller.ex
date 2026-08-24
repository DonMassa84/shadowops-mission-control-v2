defmodule ShadowOpsWeb.EvidenceController do
  use Phoenix.Controller, formats: [:json]
  def index(conn, _), do: json(conn, ShadowOpsApi.evidence())
end
