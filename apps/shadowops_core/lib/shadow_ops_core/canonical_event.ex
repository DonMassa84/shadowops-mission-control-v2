defmodule ShadowOpsCore.CanonicalEvent do
  @moduledoc "Privacy-safe canonical event envelope for the local event bus."

  alias ShadowOpsCore.Correlation

  @types ~w(
    gmail.received gmail.reply_required gmail.reply_received gmail.bounce
    gmail.attachment_received github.ci_passed github.ci_failed github.evidence_updated
    whatsapp.ingested whatsapp.analysis_completed workflow.started workflow.completed
    workflow.failed service.failed service.recovered node.online node.offline agent.started
    agent.completed agent.failed approval.requested approval.granted approval.rejected
    health.document_ingested health.coverage_decision_recorded health.claim_requirements_updated
  )
  @privacy ~w(local_only metadata_only aggregate_only sanitized public)
  @forbidden_keys ~w(body content text message messages subject snippet sender recipient phone email attachment attachments raw)

  @derive Jason.Encoder
  @enforce_keys [
    :id,
    :type,
    :source,
    :resource_id,
    :occurred_at,
    :correlation_id,
    :privacy,
    :synthetic
  ]
  defstruct [
    :id,
    :type,
    :source,
    :resource_id,
    :occurred_at,
    :correlation_id,
    :privacy,
    :synthetic,
    :evidence_ref,
    metadata: %{}
  ]

  def types, do: @types

  def new(attrs) when is_map(attrs) do
    with {:ok, correlation_id} <- Correlation.ensure(value(attrs, :correlation_id)) do
      event = %__MODULE__{
        id: value(attrs, :id) || event_id(),
        type: value(attrs, :type),
        source: value(attrs, :source),
        resource_id: value(attrs, :resource_id),
        occurred_at: value(attrs, :occurred_at) || DateTime.utc_now(),
        correlation_id: correlation_id,
        privacy: value(attrs, :privacy),
        synthetic: value(attrs, :synthetic),
        evidence_ref: value(attrs, :evidence_ref),
        metadata: value(attrs, :metadata) || %{}
      }

      case validate(event) do
        :ok -> {:ok, event}
        {:error, _} = error -> error
      end
    end
  end

  def new(_), do: {:error, :event_must_be_a_map}

  def validate(%__MODULE__{} = event) do
    cond do
      not (is_binary(event.id) and event.id != "") ->
        {:error, {:invalid_field, :id}}

      event.type not in @types ->
        {:error, {:invalid_field, :type}}

      not (is_binary(event.source) and event.source != "") ->
        {:error, {:invalid_field, :source}}

      not (is_binary(event.resource_id) and event.resource_id != "") ->
        {:error, {:invalid_field, :resource_id}}

      not timestamp?(event.occurred_at) ->
        {:error, {:invalid_field, :occurred_at}}

      not Correlation.valid?(event.correlation_id) ->
        {:error, {:invalid_field, :correlation_id}}

      event.privacy not in @privacy ->
        {:error, {:invalid_field, :privacy}}

      not is_boolean(event.synthetic) ->
        {:error, {:invalid_field, :synthetic}}

      not is_map(event.metadata) ->
        {:error, {:invalid_field, :metadata}}

      forbidden_metadata?(event.metadata) ->
        {:error, :private_event_metadata}

      true ->
        :ok
    end
  end

  defp forbidden_metadata?(value) when is_map(value) do
    Enum.any?(value, fn {key, child} ->
      String.downcase(to_string(key)) in @forbidden_keys or forbidden_metadata?(child)
    end)
  end

  defp forbidden_metadata?(value) when is_list(value),
    do: Enum.any?(value, &forbidden_metadata?/1)

  defp forbidden_metadata?(_), do: false
  defp timestamp?(%DateTime{}), do: true

  defp timestamp?(value) when is_binary(value),
    do: match?({:ok, _, _}, DateTime.from_iso8601(value))

  defp timestamp?(_), do: false
  defp event_id, do: "evt_" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)

  defp value(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> value
      :error -> Map.get(attrs, Atom.to_string(key))
    end
  end
end
