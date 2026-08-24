defmodule ShadowOpsCore.PrivacyGate do
  @moduledoc """
  Privacy Gate - decides IF data can cross the trust boundary.

  Policy decides IF action is allowed.
  PrivacyGate decides IF specific data crosses boundary.

  Blocks synthetic fixtures for:
  - private-key shaped data
  - bearer-token shaped data
  - API-key shaped data
  - .env-like secret material

  No real secrets in tests.
  """

  @secret_patterns [
    ~r/-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----/i,
    ~r/\b(?:api[_\s-]?key|secret[_\s-]?key|access[_\s-]?token|auth[_\s-]?token|bearer[_\s-]?token|password)\s*[=:]\s*\S+/i,
    ~r/\bauthorization\s*:\s*bearer\s+\S+/i,
    ~r/\bbearer\s+[A-Za-z0-9._~+\/=\-]{8,}/i
  ]

  @allowlisted_keys ~w(
    public_key
    certificate
    cert
    pub
  )

  @doc """
  Checks if data is safe to cross trust boundary.
  Returns {:ok, :allowed} or {:error, :blocked, reason}.
  """
  def check(data) when is_binary(data), do: check_string(data)

  def check(data) when is_map(data) do
    Enum.reduce_while(data, {:ok, :allowed}, fn {key, value}, acc ->
      case check_key_value(key, value) do
        {:ok, :allowed} -> {:cont, acc}
        {:error, :blocked, reason} -> {:halt, {:error, :blocked, reason}}
      end
    end)
  end

  def check(data) when is_list(data) do
    Enum.reduce_while(data, {:ok, :allowed}, fn item, acc ->
      case check(item) do
        {:ok, :allowed} -> {:cont, acc}
        {:error, :blocked, reason} -> {:halt, {:error, :blocked, reason}}
      end
    end)
  end

  def check(_other), do: {:ok, :allowed}

  defp check_string(str) do
    Enum.reduce_while(@secret_patterns, {:ok, :allowed}, fn pattern, acc ->
      if Regex.match?(pattern, str) do
        {:halt, {:error, :blocked, "secret_pattern_match: #{inspect(pattern)}"}}
      else
        {:cont, acc}
      end
    end)
  end

  defp check_key_value(key, value) do
    key_str = to_string(key)

    cond do
      secret_key?(key_str) and not allowlisted_key?(key_str) ->
        {:error, :blocked, "suspicious_key: #{key_str}"}

      true ->
        check(value)
    end
  end

  defp secret_key?(key) do
    normalized = String.downcase(key)

    String.contains?(normalized, "secret") or
      String.contains?(normalized, "password") or
      String.contains?(normalized, "token") or
      String.contains?(normalized, "key") or
      String.contains?(normalized, "credential")
  end

  defp allowlisted_key?(key) do
    normalized = String.downcase(key)
    Enum.any?(@allowlisted_keys, &String.contains?(normalized, &1))
  end
end
