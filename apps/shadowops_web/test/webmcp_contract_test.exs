defmodule ShadowOpsWeb.WebMCPContractTest do
  use ExUnit.Case, async: true

  alias ShadowOpsWeb.Plugs.WebMCPHeaders

  @root Path.expand("../../..", __DIR__)
  @asset Path.join(@root, "apps/shadowops_web/priv/static/assets/mission-control.js")

  test "browser WebMCP headers keep tools same-origin and origin-keyed" do
    conn = Plug.Test.conn(:get, "/") |> WebMCPHeaders.call([])

    assert Plug.Conn.get_resp_header(conn, "origin-agent-cluster") == ["?1"]
    assert Plug.Conn.get_resp_header(conn, "permissions-policy") == ["tools=(self)"]
  end

  test "WebMCP uses the current document.modelContext API" do
    js = File.read!(@asset)

    assert js =~ "document.modelContext"
    assert js =~ "registerTool"
    refute js =~ "navigator.modelContext"
  end

  test "WebMCP exports only bounded read-only API tools" do
    js = File.read!(@asset)

    for tool <- [
          "shadowops_health",
          "shadowops_readiness",
          "shadowops_overview",
          "shadowops_workflows",
          "shadowops_runs",
          "shadowops_jobs",
          "shadowops_nodes",
          "shadowops_services",
          "shadowops_integrations",
          "shadowops_connectors",
          "shadowops_evidence",
          "shadowops_focus",
          "shadowops_approvals",
          "shadowops_audit",
          "shadowops_logs",
          "shadowops_security"
        ] do
      assert js =~ tool
    end

    for endpoint <- ["/api/jobs", "/api/integrations", "/api/connectors", "/api/evidence", "/api/learning/plan"] do
      assert js =~ endpoint
    end

    assert js =~ "readOnlyHint: true"
    assert js =~ "untrustedContentHint: true"
    assert js =~ "AUTH_REQUIRED"
    assert js =~ "[REDACTED]"
    assert js =~ "WEBMCP_MAX_OUTPUT"
    assert js =~ "method: \"GET\""
    refute js =~ "method: \"POST\""
    refute js =~ "method: \"PUT\""
    refute js =~ "method: \"DELETE\""
  end
end
