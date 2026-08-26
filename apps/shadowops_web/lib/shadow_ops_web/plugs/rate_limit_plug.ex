defmodule ShadowOpsWeb.Plugs.RateLimitPlug do
  @moduledoc """
  Actor-scoped Hammer rate limiting for sensitive ShadowOps write/control-plane routes.

  The plug runs after write authentication. It is fail-closed when no canonical actor is
  available and every allow/deny decision is written to the append-only audit chain.
  """

  import Plug.Conn

  alias ShadowOpsCore.Audit
  alias ShadowOpsWeb.RateLimit

  @default_scale_ms 60_000
  @default_limit 30

  def init(opts),
    do: %{
      scale_ms: Keyword.get(opts, :scale_ms, @default_scale_ms),
      limit: Keyword.get(opts, :limit, @default_limit)
    }

  def call(conn, %{scale_ms: scale_ms, limit: limit}) do
    case resolve_actor(conn) do
      {:ok, actor} -> check_limit(conn, actor, scale_ms, limit)
      :error -> deny_without_actor(conn)
    end
  end

  def call(conn, opts) when is_list(opts), do: call(conn, init(opts))

  defp check_limit(conn, actor, scale_ms, limit) do
    route = route_key(conn)
    bucket = "control-plane:#{route}:#{actor}"

    case RateLimit.hit(bucket, scale_ms, limit) do
      {:allow, count} ->
        case audit_decision(actor, route, :allow, count, limit, nil) do
          :ok -> conn
          {:error, _reason} -> audit_unavailable(conn)
        end

      {:deny, retry_after_ms} ->
        case audit_decision(actor, route, :deny, limit, limit, retry_after_ms) do
          :ok ->
            conn
            |> put_resp_header("retry-after", retry_after_seconds(retry_after_ms))
            |> json_error(429, "rate_limited")

          {:error, _reason} ->
            audit_unavailable(conn)
        end
    end
  end

  defp deny_without_actor(conn) do
    route = route_key(conn)

    case audit_decision("unresolved", route, :deny, 0, @default_limit, nil) do
      :ok -> json_error(conn, 429, "rate_limited_no_actor")
      {:error, _reason} -> audit_unavailable(conn)
    end
  end

  defp resolve_actor(%Plug.Conn{assigns: %{actor: actor}})
       when is_binary(actor) and byte_size(actor) in 1..120,
       do: {:ok, actor}

  defp resolve_actor(%Plug.Conn{assigns: %{current_actor: %{id: actor}}})
       when is_binary(actor) and byte_size(actor) in 1..120,
       do: {:ok, actor}

  defp resolve_actor(_conn), do: :error

  # Dynamic identifiers must not create fresh buckets and bypass the per-route limit.
  defp route_key(%Plug.Conn{method: method, path_info: ["api", "approvals"]}),
    do: "#{method}:/api/approvals"

  defp route_key(%Plug.Conn{method: method, path_info: ["api", "approvals", _id, action]})
       when action in ["approve", "reject"],
       do: "#{method}:/api/approvals/:id/#{action}"

  defp route_key(%Plug.Conn{method: method, path_info: ["api", "workflows", _id, "run"]}),
    do: "#{method}:/api/workflows/:id/run"

  defp route_key(%Plug.Conn{
         method: method,
         path_info: ["api", "nodes", _id, "actions", _action]
       }),
       do: "#{method}:/api/nodes/:id/actions/:action"

  defp route_key(%Plug.Conn{
         method: method,
         path_info: ["api", "services", _id, "actions", _action]
       }),
       do: "#{method}:/api/services/:id/actions/:action"

  defp route_key(conn), do: "#{conn.method}:#{conn.request_path}"

  defp audit_decision(actor, route, decision, count, limit, retry_after_ms) do
    result = if decision == :allow, do: :success, else: :blocked

    case Audit.record(:policy_evaluated, actor, "rate_limit:#{route}", result, %{
           gate: "rate_limit",
           decision: decision,
           count: count,
           limit: limit,
           retry_after_ms: retry_after_ms,
           risk_level: "control_plane"
         }) do
      {:ok, _entry} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp audit_unavailable(conn), do: json_error(conn, 503, "rate_limit_audit_unavailable")

  defp json_error(conn, status, error) do
    body = Jason.encode!(%{error: error})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
    |> halt()
  end

  defp retry_after_seconds(value) when is_integer(value) and value > 0,
    do: value |> Kernel.+(999) |> div(1_000) |> max(1) |> Integer.to_string()

  defp retry_after_seconds(_value), do: "1"
end
