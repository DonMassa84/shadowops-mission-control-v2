defmodule ShadowOpsCore.KaliGitHubBridgeContractTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../..", __DIR__)
  @bridge Path.join(@root, "scripts/shadowops-kali-github-bridge.py")

  test "bridge self-test covers transport, replay, approval, and production boundaries" do
    {output, rc} = System.cmd("python3", [@bridge, "--self-test"], stderr_to_stdout: true)

    assert rc == 0, output
    assert output =~ "KALI_BRIDGE_SELF_TEST=PASS"

    for gate <- [
          "VALID_TASK=PASS",
          "EXECUTABLE_PATH_INJECTION=PASS",
          "SYSTEMD_UNIT_INJECTION=PASS",
          "SHELL_TEXT_REMAINS_DATA=PASS",
          "PRODUCTION_4013_BLOCK=PASS",
          "L2_APPROVAL_REQUIRED=PASS",
          "DEDUP=PASS",
          "NEW_REVISION=PASS",
          "REVISION_CONFLICT=PASS",
          "STALE_REVISION=PASS",
          "REVOCATION=PASS",
          "RECOVERY_REVOKED_STATE=PASS",
          "APPROVAL_SINGLE_USE=PASS",
          "APPROVAL_REPLAY_BLOCKED=PASS"
        ] do
      assert output =~ gate
    end
  end

  test "bridge never evaluates GitHub task text as a shell command" do
    bridge = File.read!(@bridge)

    assert bridge =~ "subprocess.run([str(worker), \"--enqueue\", envelope]"
    assert bridge =~ "SCOPE_NOT_ALLOWLISTED"
    assert bridge =~ "CAPABILITY_NOT_ALLOWLISTED"
    assert bridge =~ "APPROVAL_ALREADY_CONSUMED"
    assert bridge =~ "PRODUCTION_4013_TARGET"
    assert bridge =~ "4013_MUTATION=NO"
    refute bridge =~ "shell=True"
    refute bridge =~ "os.system("
    refute bridge =~ "eval("
    refute bridge =~ "exec("
  end

  test "bridge uses append-only state and status-only GitHub publication" do
    bridge = File.read!(@bridge)

    assert bridge =~ "os.O_EXCL"
    assert bridge =~ "os.O_APPEND"
    assert bridge =~ "approvals/pending"
    assert bridge =~ "approvals/consumed"
    assert bridge =~ "os.replace(src, dst)"
    assert bridge =~ "repos/{repo}/issues/{item}/comments"
    assert bridge =~ "KALI_RESULT_BEGIN"
    assert bridge =~ "KALI_EVIDENCE_SHA256"
    assert bridge =~ "KALI_GITHUB_STATUS_PUBLISH=PASS"
  end
end
