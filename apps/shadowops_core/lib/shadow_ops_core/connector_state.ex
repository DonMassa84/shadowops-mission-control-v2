defmodule ShadowOpsCore.ConnectorState do
  @moduledoc "Canonical evidence-backed state contract for every ShadowOps module connector."

  @statuses ~w(READY DEGRADED UNAVAILABLE UNKNOWN CONFIGURATION_REQUIRED OPTIONAL_UNAVAILABLE)
  @positive ~w(READY)
  @non_live_source_types ~w(HISTORICAL ANALYTICS_ONLY IMPORT)

  @derive Jason.Encoder
  @enforce_keys [:id, :name, :kind, :status, :health, :source, :source_type]
  defstruct [
    :id,
    :name,
    :kind,
    :status,
    :health,
    :source,
    :source_type,
    :last_sync_at,
    :last_success_at,
    :latency_ms,
    :record_count,
    :error_code,
    :error_message,
    real_data: false,
    synthetic: false,
    enabled: true,
    reachable: false,
    metadata: %{}
  ]

  def statuses, do: @statuses

  def new(attrs) when is_map(attrs) do
    normalized = normalize(attrs)

    with :ok <- required(normalized),
         :ok <- valid_status(normalized.status),
         :ok <- valid_flags(normalized),
         :ok <- valid_count(normalized.record_count),
         :ok <- positive_evidence(normalized) do
      {:ok, normalized}
    end
  end

  def new(_), do: {:error, :connector_state_must_be_a_map}

  def build(attrs) do
    case new(attrs) do
      {:ok, state} -> state
      {:error, reason} -> error_state(attrs, reason)
    end
  end

  def attach(%__MODULE__{} = state, payload) when is_map(payload),
    do: state |> Map.from_struct() |> Map.merge(payload)

  defp normalize(attrs) do
    %__MODULE__{
      id: value(attrs, :id),
      name: value(attrs, :name),
      kind: value(attrs, :kind),
      status: canonical_status(value(attrs, :status)),
      health: upper(value(attrs, :health)),
      source: value(attrs, :source),
      source_type: upper(value(attrs, :source_type)),
      real_data: value(attrs, :real_data, false),
      synthetic: value(attrs, :synthetic, false),
      enabled: value(attrs, :enabled, true),
      reachable: value(attrs, :reachable, false),
      last_sync_at: value(attrs, :last_sync_at),
      last_success_at: value(attrs, :last_success_at),
      latency_ms: value(attrs, :latency_ms),
      record_count: value(attrs, :record_count),
      error_code: value(attrs, :error_code),
      error_message: value(attrs, :error_message),
      metadata: value(attrs, :metadata, %{})
    }
  end

  defp required(state) do
    if Enum.all?(
         [state.id, state.name, state.kind, state.status, state.health, state.source_type],
         &(is_binary(&1) and &1 != "")
       ),
       do: :ok,
       else: {:error, :missing_required_connector_field}
  end

  defp valid_status(status) when status in @statuses, do: :ok
  defp valid_status(_), do: {:error, :invalid_connector_status}

  defp valid_flags(state) do
    if Enum.all?(
         [state.real_data, state.synthetic, state.enabled, state.reachable],
         &is_boolean/1
       ),
       do: :ok,
       else: {:error, :invalid_connector_flags}
  end

  defp valid_count(nil), do: :ok
  defp valid_count(count) when is_integer(count) and count >= 0, do: :ok
  defp valid_count(_), do: {:error, :invalid_record_count}

  defp positive_evidence(%{status: status} = state) when status in @positive do
    cond do
      not state.enabled -> {:error, :positive_status_for_disabled_connector}
      not state.reachable -> {:error, :positive_status_without_reachability}
      not state.real_data -> {:error, :positive_status_without_real_data}
      state.synthetic -> {:error, :synthetic_source_cannot_be_positive}
      state.source in [nil, ""] -> {:error, :positive_status_without_source}
      state.source_type in @non_live_source_types -> {:error, :non_live_source_cannot_be_positive}
      true -> :ok
    end
  end

  defp positive_evidence(_state), do: :ok

  defp error_state(attrs, reason) do
    %__MODULE__{
      id: value(attrs, :id, "invalid-connector"),
      name: value(attrs, :name, "Invalid connector"),
      kind: value(attrs, :kind, "unknown"),
      status: "UNKNOWN",
      health: "ERROR",
      source: value(attrs, :source),
      source_type: upper(value(attrs, :source_type, "UNKNOWN")),
      enabled: true,
      reachable: false,
      real_data: false,
      synthetic: false,
      error_code: "INVALID_CONNECTOR_CONTRACT",
      error_message: inspect(reason),
      metadata: %{}
    }
  end

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))

  defp upper(nil), do: nil
  defp upper(value), do: value |> to_string() |> String.upcase()

  # Older adapters used transport-specific labels. Normalize them at the
  # contract boundary so API and LiveView consumers can only observe the
  # platform status model.
  defp canonical_status(value) do
    case upper(value) do
      status when status in ["READY", "CONNECTED", "ONLINE"] ->
        "READY"

      status when status in ["DEGRADED", "ERROR"] ->
        "DEGRADED"

      status when status in ["UNAVAILABLE", "NOT_CONNECTED", "DISABLED"] ->
        "UNAVAILABLE"

      status
      when status in [
             "CONFIGURATION_REQUIRED",
             "BLOCKED_CONFIGURATION",
             "DISABLED_BY_CONFIGURATION"
           ] ->
        "CONFIGURATION_REQUIRED"

      "OPTIONAL_UNAVAILABLE" ->
        "OPTIONAL_UNAVAILABLE"

      "UNKNOWN" ->
        "UNKNOWN"

      other ->
        other
    end
  end
end
