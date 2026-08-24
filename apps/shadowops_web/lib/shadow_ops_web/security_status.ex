defmodule ShadowOpsWeb.SecurityStatus do
  @moduledoc "Runtime-derived security control status without exposing configuration secrets."

  alias ShadowOpsCore.{Audit, LearningFocus, RiskPolicy}
  alias ShadowOpsWeb.Plugs.Security

  def check do
    checks = %{
      readiness: readiness_check(),
      write_authorization: write_auth_check(),
      actor_identity: actor_identity_check(),
      approval_enforcement: approval_check(),
      audit_chain: audit_check(),
      safe_paths: safe_path_check(),
      secret_redaction: redaction_check(),
      security_headers: security_header_check(),
      unsafe_shell_interpolation: unsafe_shell_check(),
      dependency_advisories: dependency_check()
    }

    statuses = Enum.map(checks, fn {_key, value} -> value.status end)
    overall = if Enum.all?(statuses, &(&1 == "PASS")), do: "PASS", else: "DEGRADED"

    %{
      id: "security",
      name: "Security",
      kind: "security",
      status: if(overall == "PASS", do: "READY", else: "DEGRADED"),
      health: if(overall == "PASS", do: "HEALTHY", else: "DEGRADED"),
      availability: "AVAILABLE",
      overall: overall,
      checks: checks,
      source: "runtime security checks",
      source_type: "RUNTIME_SELF_CHECKS",
      real_data: true,
      synthetic: false,
      enabled: true,
      reachable: true,
      last_sync_at: nil,
      last_success_at: now(),
      latency_ms: nil,
      record_count: map_size(checks),
      error_code: nil,
      error_message: nil,
      metadata: %{},
      updated_at: now()
    }
  end

  defp readiness_check do
    registry = match?({:ok, _}, WorkflowEngine.Registry.summary())
    audit = match?({:ok, %{valid: true}}, Audit.verify())

    %{
      status: if(registry and audit, do: "PASS", else: "FAIL"),
      detail: "required registry and audit chain"
    }
  end

  defp write_auth_check do
    configured? = Application.get_env(:shadowops_web, :write_token) |> present?()

    probe =
      isolated_probe(fn ->
        Plug.Test.conn(:post, "/api/approvals") |> Security.require_write_actor([])
      end)

    fail_closed? = probe.halted and probe.status in [401, 503]

    detail =
      if configured?, do: "bearer authorization configured", else: "writes disabled fail closed"

    %{status: if(fail_closed?, do: "PASS", else: "FAIL"), detail: detail, enabled: configured?}
  end

  defp actor_identity_check do
    missing_actor =
      isolated_probe(fn ->
        Plug.Test.conn(:post, "/api/workflows/test/run")
        |> maybe_authorize()
        |> Security.require_write_actor([])
      end)

    pass? = missing_actor.halted and missing_actor.status in [400, 401, 503]

    %{
      status: if(pass?, do: "PASS", else: "FAIL"),
      detail: "write authorization probe rejects a request without actor identity"
    }
  end

  defp approval_check do
    enforced = match?({:ok, %{approval_required: true}}, RiskPolicy.get("L2"))

    %{
      status: if(enforced, do: "PASS", else: "FAIL"),
      detail: "L2/L3 workflow execution requires durable approval"
    }
  end

  defp audit_check do
    case Audit.verify() do
      {:ok, %{valid: true, entries: entries}} ->
        %{status: "PASS", detail: "hash chain valid", entries: entries}

      {:error, detail} ->
        %{status: "FAIL", detail: inspect(detail)}
    end
  end

  defp safe_path_check do
    case LearningFocus.load() do
      {:ok, %{"availability" => "AVAILABLE"}} ->
        %{status: "PASS", detail: "configured learning source accepted by allowlist"}

      _ ->
        %{status: "FAIL", detail: "configured learning source unavailable or rejected"}
    end
  end

  defp redaction_check do
    redacted =
      Security.redact(%{"token" => "control-value", "nested" => %{"password" => "control-value"}})

    pass? =
      redacted["token"] == "[REDACTED]" and
        redacted["nested"]["password"] == "[REDACTED]"

    %{
      status: if(pass?, do: "PASS", else: "FAIL"),
      detail: "recursive sensitive-field redaction self-check"
    }
  end

  defp security_header_check do
    conn = Plug.Test.conn(:get, "/api/health") |> Security.call([])

    required = [
      {"x-content-type-options", "nosniff"},
      {"x-frame-options", "DENY"},
      {"referrer-policy", "no-referrer"},
      {"cache-control", "no-store"}
    ]

    pass? =
      Enum.all?(required, fn {header, expected} ->
        Plug.Conn.get_resp_header(conn, header) == [expected]
      end)

    %{status: if(pass?, do: "PASS", else: "FAIL"), detail: "security response-header self-check"}
  end

  defp unsafe_shell_check do
    path =
      Path.expand("../../../shadowops_core/lib/shadow_ops_core/workflow_executor.ex", __DIR__)

    case File.read(path) do
      {:ok, source} ->
        system_cmd? = String.contains?(source, "System.cmd(runtime, args")
        shell? = Regex.match?(~r/System\.cmd\(("|')?(sh|bash)("|')?\s*,/i, source)

        %{
          status: if(system_cmd? and not shell?, do: "PASS", else: "FAIL"),
          detail: "workflow executor source inspection for direct argv execution"
        }

      {:error, reason} ->
        %{status: "FAIL", detail: "workflow executor source unavailable: #{inspect(reason)}"}
    end
  end

  defp dependency_check do
    path = Path.expand("../../../../docs/evidence/security_dependency_audit.json", __DIR__)

    with {:ok, body} <- File.read(path),
         {:ok, %{"status" => "PASS"}} <- Jason.decode(body) do
      %{status: "PASS", detail: "verified dependency audit evidence present"}
    else
      _ -> %{status: "NOT_CHECKED", detail: "dependency audit evidence not present"}
    end
  end

  defp present?(value), do: is_binary(value) and byte_size(value) > 0

  defp isolated_probe(probe) do
    probe
    |> Task.async()
    |> Task.await()
  end

  defp maybe_authorize(conn) do
    case Application.get_env(:shadowops_web, :write_token) do
      token when is_binary(token) and token != "" ->
        Plug.Conn.put_req_header(conn, "authorization", "Bearer " <> token)

      _ ->
        conn
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
