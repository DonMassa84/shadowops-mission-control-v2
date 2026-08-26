defmodule ShadowOpsCore.Health.DocumentIntake do
  @moduledoc """
  Local-only intake for health and insurance documents.

  Raw documents, patient identifiers, addresses, insurance numbers and free-text
  content must remain outside the repository and outside canonical event metadata.
  The intake emits only a whitelisted operational summary plus an optional local
  evidence hash/reference.
  """

  alias ShadowOpsCore.{CanonicalEvent, PrivacyGate}

  @event_types ~w(
    health.document_ingested
    health.coverage_decision_recorded
    health.claim_requirements_updated
  )

  @metadata_keys ~w(
    document_kind
    document_date
    provider_category
    payer_category
    status
    currency
    estimated_total
    approved_amount
    statutory_amount
    supplementary_amount
    expected_self_pay
    claim_documents_required
    treatment_area
    treatment_year
  )a

  @spec build_event(map(), String.t()) :: {:ok, struct()} | {:error, term()}
  def build_event(manifest, event_type \\ "health.document_ingested")
      when is_map(manifest) and event_type in @event_types do
    with {:ok, resource_id} <- required_id(manifest),
         metadata <- sanitize_metadata(manifest),
         {:ok, :allowed} <- PrivacyGate.check(metadata) do
      CanonicalEvent.new(%{
        type: event_type,
        source: "health_local",
        resource_id: resource_id,
        occurred_at: value(manifest, :occurred_at) || DateTime.utc_now(),
        correlation_id: value(manifest, :correlation_id),
        privacy: "local_only",
        synthetic: value(manifest, :synthetic) || false,
        evidence_ref: value(manifest, :evidence_ref),
        metadata: metadata
      })
    end
  end

  def build_event(_manifest, _event_type), do: {:error, :invalid_health_manifest}

  @spec sanitize_metadata(map()) :: map()
  def sanitize_metadata(manifest) when is_map(manifest) do
    Enum.reduce(@metadata_keys, %{}, fn key, acc ->
      case value(manifest, key) do
        nil -> acc
        value -> Map.put(acc, Atom.to_string(key), value)
      end
    end)
  end

  defp required_id(manifest) do
    case value(manifest, :resource_id) || value(manifest, :document_id) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:missing_field, :resource_id}}
    end
  end

  defp value(attrs, key) when is_atom(key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> value
      :error -> Map.get(attrs, Atom.to_string(key))
    end
  end
end
