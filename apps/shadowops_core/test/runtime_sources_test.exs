defmodule ShadowOpsCore.RuntimeSourcesTest do
  use ExUnit.Case, async: false

  alias ShadowOpsCore.RuntimeSources

  test "parses Docker service metadata without inventing state" do
    line =
      Jason.encode!(%{
        "Names" => "shadow-postgres",
        "State" => "running",
        "Status" => "Up 5 hours (healthy)",
        "Image" => "postgres:16"
      })

    assert {:ok, record} = RuntimeSources.parse_docker_line(line, "2026-08-23T00:00:00Z")
    assert record.name == "shadow-postgres"
    assert record.scope == "container"
    assert record.active_state == "running"
    assert record.sub_state == "Up 5 hours (healthy)"
    assert record.source == "docker"
  end

  test "rejects incomplete Docker output" do
    assert :error = RuntimeSources.parse_docker_line(~s({"Names":"missing-state"}), "now")
  end

  test "reports unavailable instead of crashing when runtime commands cannot be resolved" do
    previous_path = System.get_env("PATH")
    System.put_env("PATH", Path.join(System.tmp_dir!(), "shadowops-runtime-commands-absent"))

    on_exit(fn ->
      if previous_path,
        do: System.put_env("PATH", previous_path),
        else: System.delete_env("PATH")
    end)

    assert %{
             availability: "UNAVAILABLE",
             services: [],
             source: "systemctl --user / systemctl"
           } = RuntimeSources.services()

    assert %{
             availability: "UNAVAILABLE",
             models: [],
             source: "ollama list"
           } = RuntimeSources.ai()
  end
end
