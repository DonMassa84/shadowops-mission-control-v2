defmodule ShadowOpsWeb.DashboardCommandDeckTest do
  use ExUnit.Case, async: false

  test "dashboard renders primary command deck and governed navigation" do
    conn = Plug.Test.conn(:get, "/")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200
    assert response.resp_body =~ "Primary command deck"
    assert response.resp_body =~ "Ryzen"
    assert response.resp_body =~ "i7"
    assert response.resp_body =~ "ChatGPT nodes"
    assert response.resp_body =~ "Workflows"
    assert response.resp_body =~ "Agents"
    assert response.resp_body =~ "AI runtimes"
    assert response.resp_body =~ "Security"
    assert response.resp_body =~ "Audit"
    assert response.resp_body =~ "Command center"
    assert response.resp_body =~ "/projects/federated"
    assert response.resp_body =~ "/approvals"
    assert response.resp_body =~ "/layers"
  end
end
