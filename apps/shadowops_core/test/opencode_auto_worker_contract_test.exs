defmodule ShadowOpsCore.OpenCodeAutoWorkerContractTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../..", __DIR__)
  @worker Path.join(@root, "scripts/shadowops-opencode-auto.sh")
  @agent Path.join(@root, ".opencode/agent/shadowops-coder.md")

  test "auto-worker is queue-bound, remote-only, non-main, and never enables OpenCode blanket auto approval" do
    worker = File.read!(@worker)

    assert worker =~ "STATE_DIR=\"${SHADOWOPS_STATE_DIR:-$HOME/.local/state/shadowops}\""
    assert worker =~ "QUEUE_DIR=\"$AUTO_DIR/queue\""
    assert worker =~ "SHADOWOPS_CODER_MODEL"
    assert worker =~ "ollama/*|local/*|lmstudio/*|llamacpp/*|llama.cpp/*"
    assert worker =~ "BLOCKED_PROTECTED_BRANCH"
    assert worker =~ "BLOCKED_DIRTY_WORKTREE"
    assert worker =~ "flock -n 9"
    assert worker =~ "bash scripts/shadowops-coder.sh"
    assert worker =~ "SHADOWOPS_AUTO_TASK"
    refute worker =~ "opencode run --auto"
  end

  test "auto-worker protects control-plane boundaries and gates every commit with the full suite" do
    worker = File.read!(@worker)

    for protected <- [
          ".github/workflows/*",
          ".opencode/*",
          "docs/handoff/*",
          "ops/mcp/*",
          "config/runtime.exs",
          "scripts/shadowops-coder.sh",
          "scripts/shadowops-opencode-auto.sh",
          "apps/shadowops_core/lib/shadow_ops_core/adapters/open_code_adapter.ex",
          "apps/shadowops_core/lib/shadow_ops_core/capability_registry.ex",
          "apps/shadowops_core/lib/shadow_ops_core/execution_service.ex",
          "apps/shadowops_core/lib/shadow_ops_core/policy.ex",
          "apps/shadowops_core/lib/shadow_ops_core/risk_policy.ex",
          "apps/shadowops_core/lib/shadow_ops_core/privacy_gate.ex",
          "apps/shadowops_core/lib/shadow_ops_core/approval_store.ex",
          "apps/shadowops_core/lib/shadow_ops_core/governance_gate.ex",
          "apps/shadowops_core/lib/shadow_ops_core/audit.ex",
          "apps/shadowops_web/priv/static/assets/mission-control.js"
        ] do
      assert worker =~ protected
    end

    assert worker =~ "git diff --check"
    assert worker =~ "mix format --check-formatted"
    assert worker =~ "MIX_ENV=test mix compile --warnings-as-errors"
    assert worker =~ "MIX_ENV=test mix test"
    assert worker =~ "git commit -m \"auto(opencode): $task_id\""
    assert worker =~ "PUSHED=NO"
    assert worker =~ "MERGED=NO"
    assert worker =~ "DEPLOYED=NO"
    refute worker =~ "git push "
    refute worker =~ "git merge "
    refute worker =~ "git reset "
    refute worker =~ "git clean "
  end

  test "queued task marker overrides stale handoff tasks without weakening agent safety boundaries" do
    agent = File.read!(@agent)

    assert agent =~ "If the invocation prompt begins with `SHADOWOPS_AUTO_TASK`"
    assert agent =~ "Do not substitute or execute a stale `CURRENT TASK`"
    assert agent =~ "never relaxes the security, branch, runtime, secret, push, merge, deployment"
    assert agent =~ "explicit remote `provider/model`"
  end
end
