defmodule ShadowOpsWeb.DashboardCommandDeckTest do
  use ExUnit.Case, async: false

  test "dashboard focuses on daily operations" do
    conn = Plug.Test.conn(:get, "/")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200
    assert response.resp_body =~ "Daily operations overview"
    assert response.resp_body =~ "Do next"
    assert response.resp_body =~ "Operational gates"
    assert response.resp_body =~ "Recent runs"
    assert response.resp_body =~ "Available workflows"

    assert response.resp_body =~ "System"
    assert response.resp_body =~ "Workflows"
    assert response.resp_body =~ "Runs"
    assert response.resp_body =~ "Pending approvals"
    assert response.resp_body =~ "Nodes"
    assert response.resp_body =~ "Services"
    assert response.resp_body =~ "AI policy"
    assert response.resp_body =~ "Security"
  end

  test "primary navigation exposes recovered daily-use surfaces and hides secondary experiments" do
    conn = Plug.Test.conn(:get, "/")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200

    for path <- [
          "/compute",
          "/workflows",
          "/runs",
          "/jobs",
          "/services",
          "/backups",
          "/integrations",
          "/evidence",
          "/knowledge",
          "/approvals",
          "/security",
          "/audit",
          "/logs",
          "/focus",
          "/ai",
          "/agents"
        ] do
      assert response.resp_body =~ "href=\"#{path}\""
    end

    for path <- [
          "/layers",
          "/projects/federated",
          "/projects/chatgpt",
          "/projects/finance",
          "/projects/investigations",
          "/career",
          "/reporting",
          "/social/facebook",
          "/social/review",
          "/social/messenger",
          "/social/whatsapp",
          "/social/telegram",
          "/legal",
          "/display/i7"
        ] do
      refute response.resp_body =~ "href=\"#{path}\""
    end
  end
end
