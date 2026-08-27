defmodule ShadowOpsWeb.LocalWorkflowRegistryUiTest do
  use ExUnit.Case, async: false

  test "integrations API exposes stable local workflow registry fail closed" do
    response = ShadowOpsWeb.Endpoint.call(Plug.Test.conn(:get, "/api/integrations"), [])

    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    registry = body["local_workflow_registry"]

    assert is_map(registry)
    assert registry["source_type"] == "LOCAL_WORKFLOW_CORRELATION"
    assert registry["integration_mode"] == "REFERENCE_ONLY"
    assert registry["executable"] == false
    assert is_integer(body["local_workflow_registered_count"])
    assert body["local_workflow_registered_count"] >= 0
    assert is_integer(body["local_workflow_rejected_count"])
    assert body["local_workflow_rejected_count"] >= 0

    assert Enum.all?(registry["records"], fn record ->
             String.starts_with?(record["id"], "localwf_") and
               record["status"] == "DISCOVERED" and
               record["execution_status"] == "DISCOVERED" and
               record["executable"] == false and
               record["integration_mode"] == "REFERENCE_ONLY" and
               record["runtime_verified"] == false and
               record["governance_mapped"] == false and
               record["risk_level"] == "UNKNOWN" and
               not String.starts_with?(record["source_ref"], "/")
           end)
  end

  test "workflows page presents local IDs as safe registry evidence" do
    response = ShadowOpsWeb.Endpoint.call(Plug.Test.conn(:get, "/workflows"), [])

    assert response.status == 200
    assert response.resp_body =~ "Local IDs"
    assert response.resp_body =~ "Safe registry"
    assert response.resp_body =~ "Workflow registry"
    assert response.resp_body =~ "localwf_*"
    assert response.resp_body =~ "REFERENCE_ONLY"
  end

  test "integrations page presents registered workflow IDs separately from execution" do
    response = ShadowOpsWeb.Endpoint.call(Plug.Test.conn(:get, "/integrations"), [])

    assert response.status == 200
    assert response.resp_body =~ "Workflow IDs"
    assert response.resp_body =~ "Registered local workflow IDs"
    assert response.resp_body =~ "Evidence-first integration"
    assert response.resp_body =~ "REFERENCE_ONLY"
    assert response.resp_body =~ "inventory records, not executable workflow grants"
  end
end
