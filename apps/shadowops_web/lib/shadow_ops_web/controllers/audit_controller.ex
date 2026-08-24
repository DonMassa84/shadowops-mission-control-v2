defmodule ShadowOpsWeb.AuditController do
  use Phoenix.Controller, formats: [:json]

  alias ShadowOpsCore.Audit

  def index(conn, _params) do
    events = Audit.list()
    state = ShadowOpsApi.audit()
    json(conn, Map.merge(state, %{events: events, record_count: length(events)}))
  end

  def verify(conn, _params) do
    case Audit.verify() do
      {:ok, result} -> json(conn, result)
      {:error, result} -> conn |> put_status(:service_unavailable) |> json(result)
    end
  end

  def show(conn, %{"id" => id}) do
    case Enum.find(Audit.list(), &((Map.get(&1, :id) || Map.get(&1, "id")) == id)) do
      nil -> conn |> put_status(:not_found) |> json(%{error: "audit_entry_not_found"})
      entry -> json(conn, entry)
    end
  end
end
