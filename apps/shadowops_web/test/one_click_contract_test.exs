defmodule ShadowOpsWeb.OneClickContractTest do
  use ExUnit.Case, async: false

  alias ShadowOpsCore.ApprovalStore
  alias ShadowOpsWeb.OneClick

  setup do
    root = Path.join(System.tmp_dir!(), "shadowops-one-click-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)

    previous = %{
      enabled: Application.get_env(:shadowops_web, :one_click_enabled),
      actor: Application.get_env(:shadowops_web, :one_click_actor),
      token: Application.get_env(:shadowops_web, :write_token),
      approval: Application.get_env(:shadowops_core, :approval_path),
      audit: Application.get_env(:shadowops_core, :audit_path)
    }

    Application.put_env(:shadowops_core, :approval_path, Path.join(root, "approvals.jsonl"))
    Application.put_env(:shadowops_core, :audit_path, Path.join(root, "audit.jsonl"))

    on_exit(fn ->
      restore_web(:one_click_enabled, previous.enabled)
      restore_web(:one_click_actor, previous.actor)
      restore_web(:write_token, previous.token)
      restore_core(:approval_path, previous.approval)
      restore_core(:audit_path, previous.audit)
      File.rm_rf(root)
    end)

    :ok
  end

  test "one-click fails closed until the local write boundary is configured" do
    Application.put_env(:shadowops_web, :one_click_enabled, true)
    Application.delete_env(:shadowops_web, :write_token)

    refute OneClick.available?()
    assert {:error, :writes_disabled} = OneClick.decide_approval("missing", "approve")
  end

  test "one-click approval is an explicit durable operator decision" do
    Application.put_env(:shadowops_web, :one_click_enabled, true)
    Application.put_env(:shadowops_web, :one_click_actor, "one-click-operator")
    Application.put_env(:shadowops_web, :write_token, "one-click-test-token")

    assert OneClick.available?()

    assert {:ok, pending} =
             ApprovalStore.create(%{
               requested_by: "requester",
               action: "workflow.execute",
               resource: "repository_quality",
               reason: "one click contract",
               risk: "L2"
             })

    assert pending.status == "PENDING"
    assert {:ok, approved} = OneClick.decide_approval(pending.id, "approve")
    assert approved.status == "APPROVED"
    assert approved.decided_by == "one-click-operator"
    assert is_binary(approved.audit_ref)
  end

  test "execution surfaces are button-only without inventing runtime actions" do
    for path <- ["/workflows/repository_quality", "/services", "/compute"] do
      response = ShadowOpsWeb.Endpoint.call(Plug.Test.conn(:get, path), [])
      assert response.status == 200
      refute response.resp_body =~ ~s(name="write_token")
      refute response.resp_body =~ ~s(name="approval_id")
      refute response.resp_body =~ ~s(name="actor")
    end

    workflows = ShadowOpsWeb.Endpoint.call(Plug.Test.conn(:get, "/workflows"), [])
    assert workflows.resp_body =~ "Approve &amp; run"
    assert workflows.resp_body =~ "one_click_run"

    services = ShadowOpsWeb.Endpoint.call(Plug.Test.conn(:get, "/services"), [])
    assert services.resp_body =~ "One-click mode"
    assert services.resp_body =~ "Every supported mutation is a direct button"

    if ShadowOpsApi.services().services != [] do
      assert services.resp_body =~ "▶ Start"
      assert services.resp_body =~ "↻ Restart"
      assert services.resp_body =~ "■ Stop"
    end

    compute = ShadowOpsWeb.Endpoint.call(Plug.Test.conn(:get, "/compute"), [])
    assert compute.resp_body =~ "One-click mode"
  end

  defp restore_web(key, nil), do: Application.delete_env(:shadowops_web, key)
  defp restore_web(key, value), do: Application.put_env(:shadowops_web, key, value)
  defp restore_core(key, nil), do: Application.delete_env(:shadowops_core, key)
  defp restore_core(key, value), do: Application.put_env(:shadowops_core, key, value)
end
