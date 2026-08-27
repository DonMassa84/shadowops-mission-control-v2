defmodule ShadowOpsWeb.FeatureRecoveryActivationTest do
  use ExUnit.Case, async: false

  test "recovered daily-use surfaces render through the browser pipeline" do
    for path <- ["/compute", "/jobs", "/integrations", "/focus", "/evidence"] do
      response = ShadowOpsWeb.Endpoint.call(Plug.Test.conn(:get, path), [])
      assert response.status == 200, "expected #{path} to render, got #{response.status}"
    end
  end

  test "recovered read APIs expose source-backed state" do
    for path <- [
          "/api/jobs",
          "/api/integrations",
          "/api/connectors",
          "/api/evidence",
          "/api/learning/plan"
        ] do
      response = ShadowOpsWeb.Endpoint.call(Plug.Test.conn(:get, path), [])
      assert response.status == 200, "expected #{path} to return 200, got #{response.status}"
      assert response.resp_body != ""
    end
  end

  test "compute center exposes activated node functions as one-click buttons when runtime nodes exist" do
    response = ShadowOpsWeb.Endpoint.call(Plug.Test.conn(:get, "/compute"), [])

    assert response.status == 200
    assert response.resp_body =~ "Compute Center"
    assert response.resp_body =~ "Physical compute"
    assert response.resp_body =~ "Persistent workload queue"
    assert response.resp_body =~ "One-click mode"
    refute response.resp_body =~ ~s(name="write_token")
    refute response.resp_body =~ ~s(name="approval_id")
    refute response.resp_body =~ "Waiting for backend evidence"
    refute response.resp_body =~ ">UNVERIFIED<"

    nodes = ShadowOpsWeb.NodeCatalog.snapshot().records
    physical_nodes = Enum.reject(nodes, &ShadowOpsCore.Node.logical?/1)

    if physical_nodes != [] do
      assert response.resp_body =~ "phx-click=\"node_action\""
      assert response.resp_body =~ "↻ Check"
    else
      assert response.resp_body =~ "No physical runtime nodes were discovered"
    end
  end

  test "stop is not exposed as an activated compute action without a runtime adapter" do
    response = ShadowOpsWeb.Endpoint.call(Plug.Test.conn(:get, "/compute"), [])

    assert response.status == 200
    refute response.resp_body =~ "phx-value-action=\"stop\""
    refute response.resp_body =~ "■ Stop"
  end

  test "integration catalog keeps truthfulness metadata visible and hides retired Ollama connectors" do
    response = ShadowOpsWeb.Endpoint.call(Plug.Test.conn(:get, "/integrations"), [])

    assert response.status == 200
    assert response.resp_body =~ "Source catalog"
    assert response.resp_body =~ "Required core"
    assert response.resp_body =~ "Production ready"
    assert response.resp_body =~ "Real"
    assert response.resp_body =~ "Reachable"
    assert response.resp_body =~ "Source type"
    refute response.resp_body =~ "Local Ollama"
    refute response.resp_body =~ "i7 Ollama"
  end

  test "focus UI is backed by the configured learning plan" do
    response = ShadowOpsWeb.Endpoint.call(Plug.Test.conn(:get, "/focus"), [])

    assert response.status == 200
    assert response.resp_body =~ "Current objective, next actions and execution rules"
    assert response.resp_body =~ "Execution rules"
    assert response.resp_body =~ "KPIs"
  end
end
