defmodule ShadowOpsCore.I7RemoteExecutorTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.{I7RemoteExecutor, NodeComputeDispatcher}

  @sha String.duplicate("a", 40)

  test "executor exposes only bounded job enums" do
    assert I7RemoteExecutor.allowed_jobs() == [
             :cpu_probe,
             :format,
             :compile,
             :target_test,
             :full_test,
             :qa_bundle,
             :diff_check
           ]

    assert {:error, :job_not_allowlisted} = I7RemoteExecutor.execute(:shell, @sha)
    assert {:error, :job_not_allowlisted} = I7RemoteExecutor.execute("qa_bundle", @sha)
  end

  test "SSH arguments contain fixed target and runner plus validated enum/SHA only" do
    args = I7RemoteExecutor.ssh_args(:qa_bundle, @sha)

    assert args == [
             "-o",
             "BatchMode=yes",
             "-o",
             "ConnectTimeout=5",
             "-o",
             "ServerAliveInterval=5",
             "-o",
             "ServerAliveCountMax=2",
             "shadowserver-i7",
             "$HOME/.local/bin/shadowops-i7-executor",
             "qa_bundle",
             @sha
           ]

    refute Enum.any?(args, &String.contains?(&1, "4013"))
    refute Enum.any?(args, &String.contains?(&1, "systemctl"))
    refute Enum.any?(args, &String.contains?(&1, "bash -c"))
  end

  test "dispatcher maps compute jobs to explicit capabilities" do
    assert {:ok, "supplementary_compute"} = NodeComputeDispatcher.capability_for(:cpu_probe)
    assert {:ok, "qa"} = NodeComputeDispatcher.capability_for(:qa_bundle)
    assert {:ok, "qa"} = NodeComputeDispatcher.capability_for(:full_test)
    assert {:ok, "repository_change"} = NodeComputeDispatcher.capability_for(:diff_check)
    assert {:error, :job_not_allowlisted} = NodeComputeDispatcher.capability_for(:shell)
  end

  test "remote wrapper is fail-closed and never exposes arbitrary command input" do
    wrapper =
      Path.expand("../../../scripts/shadowops-i7-executor.sh", __DIR__)
      |> File.read!()

    assert wrapper =~ "JOB_NOT_ALLOWLISTED"
    assert wrapper =~ "EXACT_HEAD_MISMATCH"
    assert wrapper =~ "EXPECTED_SHA"
    assert wrapper =~ "I7_EXECUTOR=PASS"
    assert wrapper =~ "4013_MUTATION=NO"
    assert wrapper =~ "4014_MUTATION=NO"
    refute wrapper =~ "eval "
    refute wrapper =~ "systemctl"
    refute wrapper =~ "git reset"
    refute wrapper =~ "git clean"
    refute wrapper =~ "git checkout"
    refute wrapper =~ "git pull"
    refute wrapper =~ "git push"
  end
end
