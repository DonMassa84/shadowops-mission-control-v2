defmodule ShadowOpsWeb.WorkflowInventoryUITest do
  use ExUnit.Case, async: false

  test "Mission Control exposes focused daily operations and complete workflow inventory" do
    dashboard = request("/")
    assert dashboard.status == 200
    assert dashboard.resp_body =~ "Daily operations overview"
    assert dashboard.resp_body =~ "Current mission"
    assert dashboard.resp_body =~ "Top 3 next actions"
    assert dashboard.resp_body =~ "Operational gates"
    assert dashboard.resp_body =~ "Available workflows"
    assert dashboard.resp_body =~ "Job queue"
    assert dashboard.resp_body =~ "Compute"
    assert dashboard.resp_body =~ "AI policy"
    assert dashboard.resp_body =~ "Approvals"
    assert dashboard.resp_body =~ "Security"
    assert dashboard.resp_body =~ "Source:"
    assert dashboard.resp_body =~ "href=\"/focus\""
    assert dashboard.resp_body =~ "href=\"/integrations\""

    refute dashboard.resp_body =~ "Career pipeline"
    refute dashboard.resp_body =~ "9 canonical / 61 external"

    workflows = request("/workflows")
    assert workflows.status == 200
    assert workflows.resp_body =~ "Total workflow slots"
    assert workflows.resp_body =~ "External runtime coverage"
    assert workflows.resp_body =~ "Named in source"
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
