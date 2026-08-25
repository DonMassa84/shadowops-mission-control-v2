defmodule ShadowOpsCore.Status do
  @moduledoc """
  Canonical ShadowOps status normalization and classification.

  Domain modules may keep their precise state names, but classification for UI,
  readiness summaries, and policy decisions must pass through this module instead
  of maintaining independent status lists.
  """

  @positive ~w(PASS VALID AVAILABLE CONNECTED ONLINE SUCCESS APPROVED READY VERIFIED HEALTHY ACTIVE EXCELLENT)
  @error ~w(FAIL INVALID ERROR OFFLINE FAILED REJECTED BLOCKED BLOCKED_CONFIGURATION CRITICAL)
  @degraded ~w(PENDING RUNNING QUEUED DEGRADED PARTIAL REVIEW WARN WARNING)
  @unavailable ~w(NOT_ASSESSED NOT_CONFIGURED NOT_CONNECTED UNAVAILABLE UNKNOWN NOT_CHECKED EXPIRED DISABLED DISABLED_BY_CONFIGURATION)

  @type category :: :positive | :error | :degraded | :unavailable | :neutral

  @spec normalize(term()) :: String.t()
  def normalize(value) when is_atom(value), do: value |> Atom.to_string() |> String.upcase()
  def normalize(value) when is_binary(value), do: String.upcase(value)
  def normalize(nil), do: "UNKNOWN"
  def normalize(value), do: value |> to_string() |> String.upcase()

  @spec category(term()) :: category()
  def category(value) do
    normalized = normalize(value)

    cond do
      normalized in @positive -> :positive
      normalized in @error -> :error
      normalized in @degraded -> :degraded
      normalized in @unavailable -> :unavailable
      true -> :neutral
    end
  end

  @spec positive?(term()) :: boolean()
  def positive?(value), do: category(value) == :positive

  @spec failed?(term()) :: boolean()
  def failed?(value), do: category(value) == :error

  @spec degraded?(term()) :: boolean()
  def degraded?(value), do: category(value) == :degraded

  @spec unavailable?(term()) :: boolean()
  def unavailable?(value), do: category(value) == :unavailable

  @spec tone(term()) :: String.t()
  def tone(value) do
    case category(value) do
      :positive -> "success"
      :error -> "error"
      :degraded -> "review"
      :unavailable -> "muted"
      :neutral -> "neutral"
    end
  end
end
