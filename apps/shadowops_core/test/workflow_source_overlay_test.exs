defmodule ShadowOpsCore.WorkflowSourceOverlayTest do
  use ExUnit.Case, async: false

  alias ShadowOpsCore.WorkflowSource

  setup do
    previous =
      System.get_env("SHADOWOPS_LOCAL_WORKFLOW_OVERLAY")

    on_exit(fn ->
      if previous do
        System.put_env(
          "SHADOWOPS_LOCAL_WORKFLOW_OVERLAY",
          previous
        )
      else
        System.delete_env("SHADOWOPS_LOCAL_WORKFLOW_OVERLAY")
      end
    end)

    :ok
  end

  test "base registry loads with overlay disabled" do
    System.delete_env("SHADOWOPS_LOCAL_WORKFLOW_OVERLAY")

    assert {:ok, registry} =
             WorkflowSource.load()

    assert is_map(registry["workflows"])
  end

  test "local overlay merges without overriding base" do
    {:ok, base} =
      WorkflowSource.load_base()

    {existing_id, existing} =
      Enum.at(
        base["workflows"],
        0
      )

    path =
      Path.join(
        System.tmp_dir!(),
        "shadowops-overlay-test-#{System.unique_integer([:positive])}.json"
      )

    payload = %{
      "workflows" => %{
        "__overlay_test__" => %{
          "type" => "system",
          "domain" => "test",
          "status" => "VERIFIED_EXECUTABLE",
          "risk_level" => "L0",
          "runtime" => "/bin/true"
        },
        existing_id => %{
          "status" => "BROKEN_OVERRIDE"
        }
      }
    }

    File.write!(
      path,
      Jason.encode!(payload)
    )

    System.put_env(
      "SHADOWOPS_LOCAL_WORKFLOW_OVERLAY",
      path
    )

    assert {:ok, merged} =
             WorkflowSource.load()

    assert Map.has_key?(
             merged["workflows"],
             "__overlay_test__"
           )

    assert merged["workflows"][existing_id] ==
             existing

    File.rm(path)
  end
end
