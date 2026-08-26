defmodule ShadowOpsWeb.DashboardCommandDeckTest do
  use ExUnit.Case, async: false

  test "V2 dashboard exposes mission, attention, actions and source truth" do
    response =
      :get
      |> Plug.Test.conn("/")
      |> ShadowOpsWeb.Endpoint.call([])

    assert response.status == 200
    body = response.resp_body

    assert body =~ "Mission Control"
    assert body =~ ~r/current mission/i
    assert body =~ ~r/attention required/i
    assert body =~ ~r/top 3/i
    assert body =~ ~r/source truth/i
    assert body =~ ~r/daily control/i

    assert body =~ "IHK"
    assert body =~ "Evidence"
    assert body =~ "Knowledge"
    assert body =~ "Services"

    refute body =~ "/home/schattenmacher/"
  end

  test "V2 primary navigation exposes command, operations, intelligence and governance" do
    response =
      :get
      |> Plug.Test.conn("/")
      |> ShadowOpsWeb.Endpoint.call([])

    assert response.status == 200
    body = response.resp_body

    for path <- [
          "/daily-control",
          "/compute",
          "/workflows",
          "/runs",
          "/jobs",
          "/services",
          "/backups",
          "/knowledge",
          "/evidence",
          "/ai",
          "/agents",
          "/approvals",
          "/security",
          "/audit",
          "/logs",
          "/career",
          "/projects/ihk",
          "/integrations"
        ] do
      assert body =~ ~s(href="#{path}")
    end
  end
end
