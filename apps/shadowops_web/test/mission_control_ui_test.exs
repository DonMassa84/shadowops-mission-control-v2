defmodule ShadowOpsWeb.MissionControlUITest do
  use ExUnit.Case, async: false

  @browser_routes ~w(/ /infrastructure /workflows /runs /services /nodes /agents /ai /knowledge /career /backups /reporting /social /social/facebook /social/review /social/messenger /social/whatsapp /social/telegram /security /approvals /audit /evidence /logs)

  test "all Mission Control routes render the canonical shell and explicit source state" do
    for path <- @browser_routes do
      response = request(:get, path)
      assert response.status == 200, "#{path} returned #{response.status}"
      assert response.resp_body =~ "ShadowOps"
      assert response.resp_body =~ "Mission Control"
    end
  end

  test "workflow list exposes real registry rows, filters and detail" do
    list = request(:get, "/workflows")
    assert list.resp_body =~ "finanzabgleich"
    assert list.resp_body =~ ~s(name="search")
    assert list.resp_body =~ "Clear filters"

    detail = request(:get, "/workflows/repository_quality")
    assert detail.status == 200
    assert detail.resp_body =~ "Execution policy"
    assert detail.resp_body =~ "L2 approval required"
    assert detail.resp_body =~ "Run workflow"
    assert detail.resp_body =~ "Audit events"
  end

  test "service page exposes governed runtime controls" do
    services = request(:get, "/services")
    assert services.status == 200
    assert services.resp_body =~ "Governed service control"
    assert services.resp_body =~ "Execute service action"
    assert services.resp_body =~ ~s(type="password" name="write_token")
  end

  test "daily digest is available through the canonical workflow lookup" do
    assert {:ok, workflow} = ShadowOpsApi.get_workflow("daily_digest")
    assert workflow["id"] == "daily_digest"
    assert workflow["status"] == "VERIFIED_EXECUTABLE"
  end

  test "durable empty states do not generate operational records" do
    previous_run = Application.get_env(:shadowops_core, :run_path)
    previous_approval = Application.get_env(:shadowops_core, :approval_path)

    root =
      Path.join(System.tmp_dir!(), "shadowops-ui-empty-#{System.unique_integer([:positive])}")

    Application.put_env(:shadowops_core, :run_path, Path.join(root, "runs.jsonl"))
    Application.put_env(:shadowops_core, :approval_path, Path.join(root, "approvals.jsonl"))

    on_exit(fn ->
      restore(:run_path, previous_run)
      restore(:approval_path, previous_approval)
      File.rm_rf(root)
    end)

    assert request(:get, "/runs").resp_body =~ "No real execution has been requested"
    assert request(:get, "/approvals").resp_body =~ "No approval has been requested"
  end

  test "optional integrations expose evidence-backed contracts without synthetic live state" do
    for path <- ~w(/api/nodes /api/agents /api/logs /api/social /api/connectors/whatsapp) do
      response = request(:get, path)
      assert response.status == 200
      body = Jason.decode!(response.resp_body)
      assert is_binary(body["status"])

      records = body["records"] || [body]

      refute Enum.any?(records, fn record ->
               record["synthetic"] == true and record["status"] in ~w(CONNECTED ONLINE READY)
             end)
    end

    evidence = request(:get, "/evidence").resp_body
    knowledge = request(:get, "/knowledge").resp_body
    refute evidence =~ "/home/"
    refute knowledge =~ "/home/"
  end

  test "security API reports real checks and unauthorized writes fail closed" do
    previous = Application.get_env(:shadowops_web, :write_token)
    Application.delete_env(:shadowops_web, :write_token)
    on_exit(fn -> restore_web(:write_token, previous) end)

    security = request(:get, "/api/security/status")
    assert security.status == 200
    body = Jason.decode!(security.resp_body)
    assert body["checks"]["actor_identity"]["status"] == "PASS"
    assert body["checks"]["secret_redaction"]["status"] == "PASS"

    denied = request(:post, "/api/workflows/repository_quality/run", %{})
    assert denied.status == 503
    assert Jason.decode!(denied.resp_body)["error"] == "writes_disabled"
  end

  test "audit detail returns string-keyed entries and unknown ids remain not found" do
    previous = Application.get_env(:shadowops_core, :audit_path)

    path =
      Path.join(
        System.tmp_dir!(),
        "shadowops-audit-detail-#{System.unique_integer([:positive])}.jsonl"
      )

    Application.put_env(:shadowops_core, :audit_path, path)

    on_exit(fn ->
      restore(:audit_path, previous)
      File.rm(path)
    end)

    assert {:ok, entry} =
             ShadowOpsCore.Audit.record(:requested, "audit-api-test", "workflow-a", :success)

    existing = request(:get, "/api/audit/#{entry.id}")
    assert existing.status == 200
    assert Jason.decode!(existing.resp_body)["id"] == entry.id

    unknown = request(:get, "/api/audit/audit_unknown")
    assert unknown.status == 404
    assert Jason.decode!(unknown.resp_body)["error"] == "audit_entry_not_found"
  end

  test "runtime configuration loads authorization tokens from the environment" do
    previous_read = System.get_env("SHADOWOPS_READ_TOKEN")
    previous_write = System.get_env("SHADOWOPS_WRITE_TOKEN")

    System.put_env("SHADOWOPS_READ_TOKEN", "runtime-read-token")
    System.put_env("SHADOWOPS_WRITE_TOKEN", "runtime-write-token")

    on_exit(fn ->
      restore_env("SHADOWOPS_READ_TOKEN", previous_read)
      restore_env("SHADOWOPS_WRITE_TOKEN", previous_write)
    end)

    config =
      __DIR__
      |> Path.join("../../../config/runtime.exs")
      |> Config.Reader.read!()

    assert get_in(config, [:shadowops_web, :read_token]) == "runtime-read-token"
    assert get_in(config, [:shadowops_web, :write_token]) == "runtime-write-token"
  end

  test "authenticated approval-gated write creates durable run and valid audit chain" do
    root =
      Path.join(System.tmp_dir!(), "shadowops-ui-write-#{System.unique_integer([:positive])}")

    previous = %{
      token: Application.get_env(:shadowops_web, :write_token),
      run: Application.get_env(:shadowops_core, :run_path),
      approval: Application.get_env(:shadowops_core, :approval_path),
      audit: Application.get_env(:shadowops_core, :audit_path)
    }

    Application.put_env(:shadowops_web, :write_token, "test-write-token")
    Application.put_env(:shadowops_core, :run_path, Path.join(root, "runs.jsonl"))
    Application.put_env(:shadowops_core, :approval_path, Path.join(root, "approvals.jsonl"))
    Application.put_env(:shadowops_core, :audit_path, Path.join(root, "audit.jsonl"))

    on_exit(fn ->
      restore_web(:write_token, previous.token)
      restore(:run_path, previous.run)
      restore(:approval_path, previous.approval)
      restore(:audit_path, previous.audit)
      File.rm_rf(root)
    end)

    created =
      authorized_request(:post, "/api/approvals", %{
        "action" => "workflow.execute",
        "resource" => "repository_quality",
        "reason" => "controlled execution test"
      })

    assert created.status == 201
    approval = Jason.decode!(created.resp_body)
    assert approval["requested_by"] == "test-operator"
    assert approval["status"] == "PENDING"

    decided = authorized_request(:post, "/api/approvals/#{approval["id"]}/approve", %{})
    assert decided.status == 200
    assert Jason.decode!(decided.resp_body)["status"] == "APPROVED"

    executed =
      authorized_request(:post, "/api/workflows/repository_quality/run", %{
        "approval_id" => approval["id"],
        "args" => []
      })

    assert executed.status == 200
    run = Jason.decode!(executed.resp_body)["run"]
    assert run["status"] == "FAILED"
    assert is_binary(run["audit_ref"])
    assert request(:get, "/api/runs/#{run["id"]}").status == 200

    verify = request(:get, "/api/audit/verify")
    assert verify.status == 200
    assert Jason.decode!(verify.resp_body)["valid"]
  end

  test "write boundary requires actor identity and invalid approval transitions stay JSON" do
    root =
      Path.join(System.tmp_dir!(), "shadowops-ui-boundary-#{System.unique_integer([:positive])}")

    previous = %{
      token: Application.get_env(:shadowops_web, :write_token),
      approval: Application.get_env(:shadowops_core, :approval_path),
      audit: Application.get_env(:shadowops_core, :audit_path)
    }

    Application.put_env(:shadowops_web, :write_token, "test-write-token")
    Application.put_env(:shadowops_core, :approval_path, Path.join(root, "approvals.jsonl"))
    Application.put_env(:shadowops_core, :audit_path, Path.join(root, "audit.jsonl"))

    on_exit(fn ->
      restore_web(:write_token, previous.token)
      restore(:approval_path, previous.approval)
      restore(:audit_path, previous.audit)
      File.rm_rf(root)
    end)

    missing_actor = token_only_request(:post, "/api/approvals", %{})
    assert missing_actor.status == 400
    assert Jason.decode!(missing_actor.resp_body)["error"] == "valid_actor_required"

    approval =
      authorized_request(:post, "/api/approvals", %{
        "action" => "workflow.execute",
        "resource" => "repository_quality",
        "reason" => "transition contract"
      })
      |> Map.fetch!(:resp_body)
      |> Jason.decode!()

    assert authorized_request(:post, "/api/approvals/#{approval["id"]}/approve", %{}).status ==
             200

    invalid = authorized_request(:post, "/api/approvals/#{approval["id"]}/reject", %{})
    assert invalid.status == 400
    assert Jason.decode!(invalid.resp_body)["error"] =~ "invalid_transition"

    expired =
      authorized_request(:post, "/api/approvals", %{
        "action" => "workflow.execute",
        "resource" => "repository_quality",
        "reason" => "expiry contract",
        "expires_at" => "2020-01-01T00:00:00Z"
      })
      |> Map.fetch!(:resp_body)
      |> Jason.decode!()

    expired_read = request(:get, "/api/approvals/#{expired["id"]}")
    assert Jason.decode!(expired_read.resp_body)["status"] == "EXPIRED"

    invalid_expiry =
      authorized_request(:post, "/api/approvals", %{
        "action" => "workflow.execute",
        "resource" => "repository_quality",
        "expires_at" => "not-a-timestamp"
      })

    assert invalid_expiry.status == 422
  end

  test "Mission Control asset contains responsive and keyboard focus rules" do
    css = request(:get, "/assets/mission-control.css")
    assert css.status == 200
    assert css.resp_body =~ "@media(max-width:900px)"
    assert css.resp_body =~ ".mc-shell{display:block}"
    assert css.resp_body =~ "@media(max-width:560px)"
    assert css.resp_body =~ "grid-template-columns:1fr"
    assert css.resp_body =~ ":focus-visible"
    assert css.resp_body =~ "prefers-reduced-motion"

    js = request(:get, "/assets/mission-control.js")
    assert js.status == 200
    assert js.resp_body =~ "new LiveSocket"

    icon = request(:get, "/assets/shadowops-mark.svg")
    assert icon.status == 200
    assert icon.resp_body =~ "ShadowOps"
    assert request(:get, "/favicon.ico").status == 200

    assert request(:get, "/vendor/phoenix/phoenix.mjs").status == 200
    assert request(:get, "/vendor/live-view/phoenix_live_view.esm.js").status == 200
  end

  defp request(method, path, params \\ nil) do
    conn =
      if params,
        do:
          Plug.Test.conn(method, path, Jason.encode!(params))
          |> Plug.Conn.put_req_header("content-type", "application/json"),
        else: Plug.Test.conn(method, path)

    ShadowOpsWeb.Endpoint.call(conn, [])
  end

  defp authorized_request(method, path, params) do
    method
    |> Plug.Test.conn(path, Jason.encode!(params))
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Plug.Conn.put_req_header("authorization", "Bearer test-write-token")
    |> Plug.Conn.put_req_header("x-shadowops-actor", "test-operator")
    |> ShadowOpsWeb.Endpoint.call([])
  end

  defp token_only_request(method, path, params) do
    method
    |> Plug.Test.conn(path, Jason.encode!(params))
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Plug.Conn.put_req_header("authorization", "Bearer test-write-token")
    |> ShadowOpsWeb.Endpoint.call([])
  end

  defp restore(key, nil), do: Application.delete_env(:shadowops_core, key)
  defp restore(key, value), do: Application.put_env(:shadowops_core, key, value)
  defp restore_web(key, nil), do: Application.delete_env(:shadowops_web, key)
  defp restore_web(key, value), do: Application.put_env(:shadowops_web, key, value)
  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
