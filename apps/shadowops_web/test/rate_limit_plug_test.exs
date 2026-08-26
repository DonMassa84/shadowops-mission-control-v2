defmodule ShadowOpsWeb.Plugs.RateLimitPlugTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias ShadowOpsCore.Audit
  alias ShadowOpsWeb.Plugs.RateLimitPlug

  setup do
    suffix = System.unique_integer([:positive, :monotonic])
    audit_path = Path.join(System.tmp_dir!(), "shadowops-rate-limit-#{suffix}.jsonl")
    old_audit_path = Application.get_env(:shadowops_core, :audit_path)
    old_write_token = Application.get_env(:shadowops_web, :write_token)

    Application.put_env(:shadowops_core, :audit_path, audit_path)

    on_exit(fn ->
      restore_env(:shadowops_core, :audit_path, old_audit_path)
      restore_env(:shadowops_web, :write_token, old_write_token)
      File.rm(audit_path)
    end)

    %{suffix: suffix}
  end

  test "under limit: request passes and decision is audited", %{suffix: suffix} do
    conn = write_conn("/api/workflows/42/run", "actor-under-#{suffix}")
    result = RateLimitPlug.call(conn, RateLimitPlug.init([]))

    refute result.halted

    [entry | _] = Audit.list(10)
    assert entry["action"] == "policy_evaluated"
    assert entry["result"] == "success"
    assert get_in(entry, ["metadata", "gate"]) == "rate_limit"
    assert get_in(entry, ["metadata", "decision"]) == "allow"
  end

  test "over limit: request is denied with 429 and Retry-After", %{suffix: suffix} do
    actor = "actor-deny-#{suffix}"
    opts = RateLimitPlug.init(limit: 30, scale_ms: 60_000)

    Enum.each(1..30, fn _ ->
      result = RateLimitPlug.call(write_conn("/api/workflows/42/run", actor), opts)
      refute result.halted
    end)

    result = RateLimitPlug.call(write_conn("/api/workflows/99/run", actor), opts)

    assert result.halted
    assert result.status == 429
    assert get_resp_header(result, "retry-after") != []
    assert Jason.decode!(result.resp_body) == %{"error" => "rate_limited"}

    [entry | _] = Audit.list(100)
    assert entry["result"] == "blocked"
    assert get_in(entry, ["metadata", "decision"]) == "deny"
  end

  test "different actors are counted independently", %{suffix: suffix} do
    actor_a = "actor-a-#{suffix}"
    actor_b = "actor-b-#{suffix}"
    opts = RateLimitPlug.init(limit: 2, scale_ms: 60_000)

    Enum.each(1..2, fn _ ->
      refute RateLimitPlug.call(write_conn("/api/approvals", actor_a), opts).halted
    end)

    assert RateLimitPlug.call(write_conn("/api/approvals", actor_a), opts).status == 429
    refute RateLimitPlug.call(write_conn("/api/approvals", actor_b), opts).halted
  end

  test "missing actor fails closed when plug is invoked directly" do
    result =
      conn(:post, "/api/approvals", Jason.encode!(%{}))
      |> put_req_header("content-type", "application/json")
      |> RateLimitPlug.call(RateLimitPlug.init([]))

    assert result.halted
    assert result.status == 429
    assert Jason.decode!(result.resp_body) == %{"error" => "rate_limited_no_actor"}
  end

  test "router authentication rejects missing actor before rate limiting" do
    token = "write-token-for-rate-limit-test-0123456789abcdef"
    Application.put_env(:shadowops_web, :write_token, token)

    response =
      conn(:post, "/api/approvals", Jason.encode!(%{}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")
      |> ShadowOpsWeb.Endpoint.call([])

    assert response.status == 400
    assert Jason.decode!(response.resp_body) == %{"error" => "valid_actor_required"}
  end

  test "authenticated write route still reaches canonical governance and approval checks", %{
    suffix: suffix
  } do
    token = "write-token-for-governance-test-0123456789abcdef"
    Application.put_env(:shadowops_web, :write_token, token)

    response =
      conn(:post, "/api/workflows/repository_quality/run", Jason.encode!(%{}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("x-shadowops-actor", "governance-actor-#{suffix}")
      |> ShadowOpsWeb.Endpoint.call([])

    assert response.status in [400, 409]
    body = Jason.decode!(response.resp_body)
    assert body["error"] in ["approval_required", "execution_failed"]

    refute Enum.any?(Audit.list(100), fn entry ->
             entry["action"] == "execution_finished" and entry["result"] == "success"
           end)
  end

  defp write_conn(path, actor) do
    conn(:post, path, Jason.encode!(%{}))
    |> put_req_header("content-type", "application/json")
    |> assign(:actor, actor)
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
