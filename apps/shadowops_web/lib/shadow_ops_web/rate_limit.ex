defmodule ShadowOpsWeb.RateLimit do
  @moduledoc "Single-node Hammer ETS limiter for the local ShadowOps control plane."

  use Hammer, backend: :ets
end
