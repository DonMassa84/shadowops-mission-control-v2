defmodule ShadowOpsCore.ServiceClassificationProjection do
  @moduledoc """
  Pure projection of canonical ServiceRuntimeCorrelation classification onto
  existing service records. Single source of truth for API and UI.

  Performs NO runtime IO. The caller must supply the already-fetched
  runtime snapshot (loaded exactly once per request).
  """

  alias ShadowOpsCore.ServiceRuntimeCorrelation

  @spec project(map(), list()) :: map()
  def project(discovery_data, runtime_snapshot) when is_list(runtime_snapshot) do
    classified_services =
      Enum.map(discovery_data.services || [], fn svc ->
        classify_service(svc, runtime_snapshot)
      end)

    %{discovery_data | services: classified_services}
  end

  @spec classify_service(map(), list()) :: map()
  def classify_service(svc, runtime_snapshot) when is_list(runtime_snapshot) do
    {:ok, classified} = ServiceRuntimeCorrelation.correlate(svc, runtime_snapshot)

    Map.merge(svc, %{
      classification_stage: classified.status,
      runtime_identity: classified.identity,
      runtime_verified: classified.runtime_verified,
      live: classified.live,
      connected: classified.connected,
      real_data: classified.real_data,
      ready: classify_ready(classified),
      definition_match: classified.definition_match,
      runtime_conflict: classified.runtime_conflict,
      runtime_ambiguous: classified.runtime_ambiguous
    })
  end

  defp classify_ready(classified) do
    classified.runtime_verified and
      classified.live and
      classified.connected and
      classified.real_data and
      classified.definition_match and
      not classified.synthetic and
      not classified.runtime_conflict and
      not classified.runtime_ambiguous
  end
end
