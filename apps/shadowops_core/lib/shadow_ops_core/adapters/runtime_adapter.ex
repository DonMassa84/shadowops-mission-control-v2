defmodule ShadowOpsCore.Adapters.RuntimeAdapter do
  @moduledoc "Common discovery, validation, execution and evidence interface for existing runtimes."

  @callback discover(keyword()) :: {:ok, list()} | {:error, term()}
  @callback status(keyword()) :: map()
  @callback validate(term()) :: :ok | {:error, term()}
  @callback run(term(), map(), map()) :: {:ok, term()} | {:error, term()}
  @callback stop(term(), map()) :: {:ok, term()} | {:error, term()}
  @callback health(term()) :: map()
  @callback evidence(term()) :: {:ok, ShadowOpsCore.Evidence.t()} | {:error, term()}
end
