defmodule ShadowOpsWeb.ComputeLive do
  use Phoenix.LiveView

  alias ShadowOpsApi

  @impl true
  def mount(_params, _session, socket) do
    overview = ShadowOpsApi.system_overview()
    socket = assign(socket, overview: overview, collected_at: System.os_time(:second))
    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    overview = ShadowOpsApi.system_overview()
    {:noreply, assign(socket, overview: overview, collected_at: System.os_time(:second))}
  end
end
