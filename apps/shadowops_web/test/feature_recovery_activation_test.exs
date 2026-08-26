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

  test "compute center replaced the static unknown placeholder" do
    response = ShadowOpsWeb.Endpoint.call(Plug.Test.conn(:get, "/compute"), [])

    assert response.status == 200
    assert response.resp_body =~ "Compute Center"
    assert response.resp_body =~ "Physical compute"
    assert response.resp_body =~ "Persistent workload queue"
    assert response.resp_body =~ "Governed node action"
    refute response.resp_body =~ "Waiting for backend evidence"
    refute response.resp_body =~ ">UNVERIFIED<"
  end

  test "stop is not exposed as an activated compute action without a runtime adapter" do
    response = ShadowOpsWeb.Endpoint.call(Plug.Test.conn(:get, "/compute"), [])

    assert response.status == 200
    assert response.resp_body =~ "Start (i7 only)"
    assert response.resp_body =~ "Stop remains hidden until a real stop adapter is implemented"
    refute response.resp_body =~ "value=\"stop\""
  end

  test "integration catalog keeps truthfulness metadata visible and hides retired Ollama connectors" do
    response = ShadowOpsWeb.Endpoint.call(Plug.Test.conn(:get, "/integrations"), [])

    assert response.status == 200
    assert response.resp_body =~ "Source catalog"
    assert response.resp_body =~ "Required core"
    assert response.resp_body =~ "Optional ready"
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
