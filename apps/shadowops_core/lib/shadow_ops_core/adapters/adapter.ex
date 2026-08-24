defmodule ShadowOpsCore.Adapters.Adapter do
  @moduledoc """
  Adapter behaviour for ExecutionService.

  All mutating adapters must implement this behaviour.
  """

  @callback execute(spec :: map(), input :: term(), context :: map()) ::
              {:ok, term()} | {:error, term()}
end
