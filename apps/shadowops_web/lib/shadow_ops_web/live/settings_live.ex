defmodule ShadowOpsWeb.SettingsLive do
  use Phoenix.LiveView

  alias ShadowOpsWeb.IntegrationCatalog

  @impl true
  def mount(_params, _session, socket) do
    catalog = IntegrationCatalog.snapshot()
    modules = Enum.filter(catalog.records, &(&1.scope == "core"))
    external = Enum.filter(catalog.records, &(&1.scope == "external"))

    socket =
      socket
      |> assign(:collected_at, System.os_time(:second))
      |> assign(:modules, modules)
      |> assign(:external_integrations, external)
      |> assign(:module_count, catalog.core_count)
      |> assign(:connector_count, catalog.external_count)
      |> assign(:ready_count, catalog.positive_count)

    {:ok, socket}
  end
end
