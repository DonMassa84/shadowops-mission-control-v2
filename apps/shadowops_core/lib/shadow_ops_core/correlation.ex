defmodule ShadowOpsCore.Correlation do
  @moduledoc "Opaque correlation identifiers shared by events, runs, approvals, audit and evidence."

  @pattern ~r/\Acorr_[0-9a-f]{32}\z/

  def generate, do: "corr_" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  def valid?(value), do: is_binary(value) and Regex.match?(@pattern, value)

  def ensure(nil), do: {:ok, generate()}

  def ensure(value),
    do: if(valid?(value), do: {:ok, value}, else: {:error, :invalid_correlation_id})
end
