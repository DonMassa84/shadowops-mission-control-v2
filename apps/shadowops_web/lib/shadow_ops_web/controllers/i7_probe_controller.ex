defmodule ShadowOpsWeb.I7ProbeController do
  use Phoenix.Controller, formats: [:html]

  def head(conn, _params), do: send_resp(conn, :ok, "")
end
