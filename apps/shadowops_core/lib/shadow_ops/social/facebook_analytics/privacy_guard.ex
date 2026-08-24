defmodule ShadowOps.Social.FacebookAnalytics.PrivacyGuard do
  @moduledoc "Explicit privacy boundary for Facebook analytics UI values."

  @sensitive_keys ~w(message messages text name first_name last_name phone email media cookie session token password credential identity identity_map profile)
  @blocked ~r/(?:@|bearer\s+|cookie|session|token|password|credential|identity\s*map)/i
  @phone_value ~r/^\+?[0-9][0-9 .()\-]{6,}$/

  def sanitize(value) when is_map(value) do
    value
    |> Enum.reject(fn {key, _value} -> sensitive_key?(key) end)
    |> Map.new(fn {key, item} -> {key, sanitize(item)} end)
  end

  def sanitize(value) when is_list(value), do: Enum.map(value, &sanitize/1)
  def sanitize(value), do: sanitize_value(value)

  def sanitize_value(value) when is_binary(value) do
    if Regex.match?(@blocked, value) or Regex.match?(@phone_value, value),
      do: "[REDACTED]",
      else: value
  end

  def sanitize_value(value), do: value

  def sensitive_key?(key) do
    normalized = key |> to_string() |> String.downcase()

    normalized in @sensitive_keys or
      String.contains?(normalized, "token") or
      String.contains?(normalized, "password") or
      String.contains?(normalized, "credential") or
      String.contains?(normalized, "cookie") or
      String.contains?(normalized, "session") or
      String.contains?(normalized, "identity")
  end
end
