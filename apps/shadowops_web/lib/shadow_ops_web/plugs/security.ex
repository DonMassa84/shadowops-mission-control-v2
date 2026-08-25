defmodule ShadowOpsWeb.Plugs.Security do
  @moduledoc "Security boundary for the local-only control plane."
  import Plug.Conn

  @sensitive ~r/(secret|token|password|passwd|cookie|authorization|credential|private[_-]?key|session)/i

  def init(opts), do: opts

  def call(conn, :require_read), do: require_read(conn, [])
  def call(conn, :require_write_actor), do: require_write_actor(conn, [])

  def call(conn, _opts) do
    conn
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header(
      "permissions-policy",
      "camera=(), microphone=(), geolocation=(), payment=(), usb=()"
    )
    |> put_resp_header("cross-origin-opener-policy", "same-origin")
    |> put_resp_header("cross-origin-resource-policy", "same-origin")
    |> put_resp_header(
      "content-security-policy",
      "default-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'; object-src 'none'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'"
    )
    |> maybe_no_store()
  end

  def require_read(conn, _opts) do
    case Application.get_env(:shadowops_web, :read_token) do
      expected when is_binary(expected) and byte_size(expected) > 0 ->
        if secure_token?(conn, expected),
          do: conn,
          else: deny(conn, 401, "read_authorization_required")

      _ ->
        conn
    end
  end

  def require_write_actor(conn, _opts) do
    expected = Application.get_env(:shadowops_web, :write_token)
    actor = get_req_header(conn, "x-shadowops-actor") |> List.first()

    cond do
      not (is_binary(expected) and byte_size(expected) > 0) ->
        deny(conn, 503, "writes_disabled")

      not secure_token?(conn, expected) ->
        deny(conn, 401, "write_authorization_required")

      not valid_actor?(actor) ->
        deny(conn, 400, "valid_actor_required")

      true ->
        assign(conn, :actor, actor)
    end
  end

  @doc "Validates per-action credentials submitted to a local LiveView without persisting them."
  def authorize_live_write(actor, supplied_token) do
    expected = Application.get_env(:shadowops_web, :write_token)

    cond do
      not (is_binary(expected) and byte_size(expected) > 0) -> {:error, :writes_disabled}
      not valid_actor?(actor) -> {:error, :valid_actor_required}
      not (is_binary(supplied_token) and byte_size(supplied_token) == byte_size(expected)) ->
        {:error, :write_authorization_required}

      not Plug.Crypto.secure_compare(supplied_token, expected) ->
        {:error, :write_authorization_required}

      true ->
        :ok
    end
  end

  def redact(value) when is_map(value),
    do:
      Map.new(value, fn {k, v} ->
        if Regex.match?(@sensitive, to_string(k)), do: {k, "[REDACTED]"}, else: {k, redact(v)}
      end)

  def redact(value) when is_list(value), do: Enum.map(value, &redact/1)
  def redact(value), do: value

  defp secure_token?(conn, expected) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> supplied] -> Plug.Crypto.secure_compare(supplied, expected)
      _ -> false
    end
  end

  defp valid_actor?(actor) when is_binary(actor),
    do: byte_size(actor) in 1..120 and String.match?(actor, ~r/^[[:print:]]+$/)

  defp valid_actor?(_actor), do: false

  defp maybe_no_store(conn) do
    if conn.request_path in ["/health", "/ready"] or
         String.starts_with?(conn.request_path, "/api/") do
      put_resp_header(conn, "cache-control", "no-store")
    else
      conn
    end
  end

  defp deny(conn, status, error),
    do: conn |> send_resp(status, Jason.encode!(%{error: error})) |> halt()
end
