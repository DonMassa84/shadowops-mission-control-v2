defmodule ShadowOpsWeb.InfrastructureLive do
  use Phoenix.LiveView

  alias ShadowOpsApi

  @impl true
  def mount(_params, _session, socket) do
    overview = ShadowOpsApi.system_overview()
    {:ok, nodes} = ShadowOpsApi.list_nodes()

    socket =
      socket
      |> assign(:overview, overview)
      |> assign(:nodes, nodes)
      |> assign(:collected_at, System.os_time(:second))

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    overview = ShadowOpsApi.system_overview()
    {:ok, nodes} = ShadowOpsApi.list_nodes()

    {:noreply,
     socket
     |> assign(:overview, overview)
     |> assign(:nodes, nodes)
     |> assign(:collected_at, System.os_time(:second))}
  end
end
