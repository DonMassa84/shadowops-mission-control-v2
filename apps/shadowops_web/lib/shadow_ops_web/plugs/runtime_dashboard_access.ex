defmodule ShadowOpsWeb.Plugs.RuntimeDashboardAccess do
  @moduledoc """
  Restricts the BEAM/Phoenix runtime dashboard to loopback clients.

  ShadowOps is a local control plane and the LiveDashboard exposes operational internals that
  should never be reachable directly from an untrusted network. Remote access belongs behind an
  authenticated tunnel or reverse proxy, not in this plug.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{remote_ip: remote_ip} = conn, _opts) do
    if loopback?(remote_ip) do
      conn
    else
      conn
      |> send_resp(:not_found, "Not Found")
      |> halt()
    end
  end

  defp loopback?({127, _, _, _}), do: true
  defp loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp loopback?(_), do: false
end
