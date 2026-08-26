defmodule ShadowOpsWeb.SourceRegistryPathSecurityTest do
  use ExUnit.Case, async: false

  alias ShadowOpsWeb.SourceRegistry

  setup do
    previous = System.get_env("SHADOWOPS_IMPORT_DIR")
    root = Path.join(System.tmp_dir!(), "shadowops-imports-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    System.put_env("SHADOWOPS_IMPORT_DIR", root)

    on_exit(fn ->
      File.rm_rf!(root)

      if previous do
        System.put_env("SHADOWOPS_IMPORT_DIR", previous)
      else
        System.delete_env("SHADOWOPS_IMPORT_DIR")
      end
    end)

    %{root: root}
  end

  test "unknown traversal-like and absolute source ids never become file paths" do
    for id <- ["../gmail", "../../etc/passwd", "/etc/passwd", "gmail/../../etc/passwd"] do
      snapshot = SourceRegistry.snapshot(id)

      assert snapshot.status == "UNAVAILABLE"
      assert snapshot.error_code == "UNKNOWN_SOURCE"
      assert snapshot.source == nil
      assert snapshot.real_data == false
      assert snapshot.reachable == false
    end
  end

  test "fixed allowlisted import file is accepted only as a regular file", %{root: root} do
    path = Path.join(root, "gmail.json")

    File.write!(
      path,
      Jason.encode!(%{
        "status" => "READY",
        "health" => "HEALTHY",
        "real_data" => true,
        "synthetic" => false,
        "reachable" => true,
        "record_count" => 1
      })
    )

    snapshot = SourceRegistry.snapshot("gmail")

    assert snapshot.status == "READY"
    assert snapshot.real_data == true
    assert snapshot.synthetic == false
    assert snapshot.reachable == true
    assert snapshot.source == path
  end

  test "symlink import evidence is rejected even when the link name is allowlisted", %{root: root} do
    outside =
      Path.join(System.tmp_dir!(), "shadowops-outside-#{System.unique_integer([:positive])}.json")

    File.write!(outside, Jason.encode!(%{"status" => "READY", "real_data" => true}))
    on_exit(fn -> File.rm(outside) end)

    :ok = File.ln_s(outside, Path.join(root, "gmail.json"))

    snapshot = SourceRegistry.snapshot("gmail")

    assert snapshot.status == "NOT_CONFIGURED"
    assert snapshot.error_code == "IMPORT_SYMLINK_REJECTED"
    assert snapshot.real_data == false
    assert snapshot.synthetic == false
    assert snapshot.reachable == false
  end
end
