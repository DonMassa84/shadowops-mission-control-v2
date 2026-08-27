defmodule ShadowOpsWeb.Plugs.WebMCPHeaders do
  @moduledoc "Browser response headers required for same-origin WebMCP tool registration."

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_header("origin-agent-cluster", "?1")
    |> put_resp_header("permissions-policy", "tools=(self)")
  end
end
