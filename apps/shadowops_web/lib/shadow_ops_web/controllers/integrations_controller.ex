defmodule ShadowOpsWeb.IntegrationsController do
  use Phoenix.Controller, formats: [:json]

  alias ShadowOpsCore.{RuntimeSources, ServiceClassificationProjection}
  alias ShadowOpsWeb.IntegrationCatalog

  def index(conn, _params) do
    catalog = IntegrationCatalog.snapshot()
    runtime_snapshot = RuntimeSources.services().services

    classified_services =
      catalog.local_discovery.records
      |> Enum.map(fn record ->
        ServiceClassificationProjection.classify_service(record, runtime_snapshot)
      end)

    json(conn, %{
      catalog
      | local_discovery: %{catalog.local_discovery | records: classified_services}
    })
  end
end
