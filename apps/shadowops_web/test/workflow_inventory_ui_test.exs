defmodule ShadowOpsWeb.WorkflowInventoryUITest do
  use ExUnit.Case, async: false

  test "Mission Control exposes production operations and complete source-backed workflow inventory" do
    dashboard = request("/")
    assert dashboard.status == 200
    assert dashboard.resp_body =~ "Production operations"
    assert dashboard.resp_body =~ "Production readiness"
    assert dashboard.resp_body =~ "Career &amp; application operations"
    assert dashboard.resp_body =~ "Governed workflow operations"
    assert dashboard.resp_body =~ "Sources &amp; integrations"
    assert dashboard.resp_body =~ "Career pipeline"
    assert dashboard.resp_body =~ "Approvals"
    assert dashboard.resp_body =~ "Audit"
    assert dashboard.resp_body =~ "Security"
    assert dashboard.resp_body =~ "Backups"
    assert dashboard.resp_body =~ "75"
    assert dashboard.resp_body =~ "14 canonical / 61 external"

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
