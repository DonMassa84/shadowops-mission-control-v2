defmodule ShadowOpsCore.Adapters.Deny do
  @moduledoc """
  Fail-closed adapter for unsupported or missing executors.
  It performs no external side effect.
  """

  @behaviour ShadowOpsCore.Adapters.Adapter

  @impl true
  def execute(spec, _input, _context) do
    executor =
      if is_map(spec) do
        Map.get(spec, :executor) || Map.get(spec, "executor")
      else
        nil
      end

    {:error, {:unsupported_executor, executor}}
  end
end
