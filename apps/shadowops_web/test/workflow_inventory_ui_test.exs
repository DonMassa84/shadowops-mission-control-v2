defmodule ShadowOpsWeb.WorkflowInventoryUITest do
  use ExUnit.Case, async: false

  test "Mission Control V2 keeps workflow inventory in workflow drill-down" do
    dashboard = request("/")

    assert dashboard.status == 200
    assert dashboard.resp_body =~ "Mission Control"
    assert dashboard.resp_body =~ ~r/current mission/i
    assert dashboard.resp_body =~ ~r/attention required/i
    assert dashboard.resp_body =~ ~r/source truth/i
    assert dashboard.resp_body =~ ~s(href="/workflows")

    workflows = request("/workflows")

    assert workflows.status == 200
    assert workflows.resp_body =~ "Total workflow slots"
    assert workflows.resp_body =~ "External runtime coverage"
    assert workflows.resp_body =~ "Named workflows"
    assert workflows.resp_body =~ "shadowmaker_tasks"
    assert workflows.resp_body =~ "whatsapp_agent_pack"
    assert workflows.resp_body =~ "opencode_standard"
    assert workflows.resp_body =~ "telegram_workflow_controller"
    assert workflows.resp_body =~ "whatsapp-status"
    assert workflows.resp_body =~ "whatsapp-purge-expired"
    assert workflows.resp_body =~ "EXTERNAL_REGISTRY_ONLY"
  end

  defp request(path) do
    :get
    |> Plug.Test.conn(path)
    |> ShadowOpsWeb.Endpoint.call([])
  end
end
