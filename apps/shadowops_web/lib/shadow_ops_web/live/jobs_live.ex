defmodule ShadowOpsWeb.JobsLive do
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, jobs: [], collected_at: System.os_time(:second))
    {:ok, socket}
  end
end
