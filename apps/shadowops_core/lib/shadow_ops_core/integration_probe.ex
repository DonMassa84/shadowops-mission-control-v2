defmodule ShadowOpsCore.IntegrationProbe do
  @moduledoc """
  Behaviour for application health probes.

  Each probe checks a specific service endpoint and returns evidence
  of connectivity and real data. No generic network scans.
  """

  @type evidence :: %{
          gate: String.t(),
          result: String.t(),
          evidence_ref: String.t(),
          real_data: boolean(),
          reachable: boolean()
        }

  @callback probe(map()) ::
              {:ok, evidence()}
              | {:error, term()}
              | :not_configured
end
