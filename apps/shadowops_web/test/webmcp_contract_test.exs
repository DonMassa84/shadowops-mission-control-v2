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

  test "WebMCP covers every canonical read API capability plus a global acceptance probe" do
    js = File.read!(@asset)

    for tool <- [
          "shadowops_health",
          "shadowops_readiness",
          "shadowops_overview",
          "shadowops_layers",
          "shadowops_layer",
          "shadowops_projects",
          "shadowops_system",
          "shadowops_integrations",
          "shadowops_workflows",
          "shadowops_workflow",
          "shadowops_runs",
          "shadowops_run",
          "shadowops_run_evaluation",
          "shadowops_jobs",
          "shadowops_nodes",
          "shadowops_node",
          "shadowops_services",
          "shadowops_service",
          "shadowops_agents",
          "shadowops_ai_status",
          "shadowops_ai_models",
          "shadowops_security",
          "shadowops_audit",
          "shadowops_audit_verify",
          "shadowops_audit_entry",
          "shadowops_logs",
          "shadowops_knowledge",
          "shadowops_evidence",
          "shadowops_legal",
          "shadowops_focus",
          "shadowops_approvals",
          "shadowops_approval",
          "shadowops_connectors",
          "shadowops_whatsapp",
          "shadowops_connector",
          "shadowops_social",
          "shadowops_facebook_balance",
          "shadowops_career",
          "shadowops_backups",
          "shadowops_reports",
          "shadowops_webmcp_check"
        ] do
      assert js =~ tool
    end

    for endpoint <- [
          "/api/health",
          "/api/ready",
          "/api/system/overview",
          "/api/layers",
          "/api/layers/:id",
          "/api/projects",
          "/api/system",
          "/api/integrations",
          "/api/workflows",
          "/api/workflows/:id",
          "/api/runs",
          "/api/runs/:id",
          "/api/runs/:id/evaluation",
          "/api/jobs",
          "/api/nodes",
          "/api/nodes/:id",
          "/api/services",
          "/api/services/:id",
          "/api/agents",
          "/api/ai/status",
          "/api/ai/models",
          "/api/security/status",
          "/api/audit",
          "/api/audit/verify",
          "/api/audit/:id",
          "/api/logs/recent",
          "/api/knowledge",
          "/api/evidence",
          "/api/legal",
          "/api/learning/plan",
          "/api/approvals",
          "/api/approvals/:id",
          "/api/connectors",
          "/api/connectors/whatsapp",
          "/api/connectors/:id",
          "/api/social",
          "/api/social/facebook/balance",
          "/api/career",
          "/api/backups",
          "/api/reports"
        ] do
      assert js =~ endpoint
    end
  end

  test "WebMCP remains bounded, cancellable, redacted and strictly read-only" do
    js = File.read!(@asset)

    assert js =~ "readOnlyHint: true"
    assert js =~ "untrustedContentHint: true"
    assert js =~ "AUTH_REQUIRED"
    assert js =~ "[REDACTED]"
    assert js =~ "WEBMCP_MAX_OUTPUT"
    assert js =~ "encodeURIComponent"
    assert js =~ "context.signal"
    assert js =~ "method: \"GET\""
    assert js =~ "runShadowOpsWebMcpCheck"
    refute js =~ "method: \"POST\""
    refute js =~ "method: \"PUT\""
    refute js =~ "method: \"PATCH\""
    refute js =~ "method: \"DELETE\""
  end
end
