defmodule ShadowOpsWeb.LegalRegistry do
  @moduledoc """
  Read-only, redacted Legal registry for ShadowOps Mission Control.

  The registry intentionally exposes metadata only. Original correspondence,
  banking data, payment proofs and case files remain outside Git in the local
  private evidence store.
  """

  @registry_path Path.expand("../../../../priv/legal/cases.json", __DIR__)

  def snapshot do
    with {:ok, body} <- File.read(@registry_path),
         {:ok, data} <- Jason.decode(body),
         :ok <- validate(data) do
      cases = Map.get(data, "cases", [])

      %{
        id: "legal",
        name: "Legal / Evidence",
        kind: "legal",
        status: "READY",
        health: "HEALTHY",
        availability: "AVAILABLE",
        state: "REDACTED_METADATA",
        source: "priv/legal/cases.json",
        source_type: "LOCAL_REDACTED_REGISTRY",
        real_data: true,
        synthetic: false,
        enabled: true,
        reachable: true,
        updated_at: Map.get(data, "generated_at"),
        record_count: length(cases),
        records: Enum.map(cases, &redacted_case/1),
        privacy: %{
          classification: "LEGAL_PRIVATE",
          public_payload: "REDACTED_METADATA",
          bank_data: false,
          payment_proofs: false,
          full_correspondence: false,
          original_case_files: false,
          local_private_store_required: true
        }
      }
    else
      {:error, reason} -> unavailable(reason)
    end
  end

  defp validate(%{"classification" => "REDACTED_METADATA", "cases" => cases})
       when is_list(cases),
       do: :ok

  defp validate(_), do: {:error, :invalid_registry_schema}

  defp redacted_case(case) do
    case
    |> Map.drop(["private_source"])
    |> Map.put("private_source", "LOCAL_PRIVATE_STORE")
  end

  defp unavailable(reason) do
    %{
      id: "legal",
      name: "Legal / Evidence",
      kind: "legal",
      status: "UNAVAILABLE",
      health: "ERROR",
      availability: "UNAVAILABLE",
      state: "FAIL_CLOSED",
      source: "priv/legal/cases.json",
      source_type: "LOCAL_REDACTED_REGISTRY",
      real_data: false,
      synthetic: false,
      enabled: true,
      reachable: false,
      updated_at: nil,
      record_count: 0,
      records: [],
      error_code: "LEGAL_REGISTRY_UNAVAILABLE",
      error_message: inspect(reason),
      privacy: %{
        classification: "LEGAL_PRIVATE",
        fail_closed: true
      }
    }
  end
end
