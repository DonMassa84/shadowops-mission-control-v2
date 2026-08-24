defmodule ShadowOpsWeb.MetricsController do
  use Phoenix.Controller, formats: [:html]

  alias ShadowOpsWeb.PrometheusExporter

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, PrometheusExporter.render())
  end
end
