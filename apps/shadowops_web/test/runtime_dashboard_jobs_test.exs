defmodule ShadowOpsWeb.RuntimeDashboardJobsTest do
  use ExUnit.Case, async: false

  test "runtime dashboard is available on loopback" do
    conn = Plug.Test.conn(:get, "/runtime")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200
    assert response.resp_body =~ "Phoenix LiveDashboard"
  end

  test "runtime dashboard fails closed for non-loopback clients" do
    conn = %{Plug.Test.conn(:get, "/runtime") | remote_ip: {10, 20, 30, 40}}
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 404
  end

  test "jobs surface reports persistence truthfully when disabled" do
    previous = Application.get_env(:shadowops_core, :start_persistence, false)
    Application.put_env(:shadowops_core, :start_persistence, false)

    on_exit(fn -> Application.put_env(:shadowops_core, :start_persistence, previous) end)

    conn = Plug.Test.conn(:get, "/jobs")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200
    assert response.resp_body =~ "Persistent jobs"
    assert response.resp_body =~ "NOT_CONFIGURED"
    assert response.resp_body =~ "SHADOWOPS_START_PERSISTENCE"
  end
end
