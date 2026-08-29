defmodule AgentRuntime.MessageEnvelope do
  @moduledoc """
  Message envelope for CommunicationBus transport between workers.
  
  Headless communication: Qwen <-> Nemo via LocalQueue/Router
  DISPLAY_DEPENDENCY=0
  """

  @type message_type :: :task_assign | :task_accept | :task_result | :task_failed | :worker_heartbeat | :worker_status

  @enforce_keys [:message_id, :correlation_id, :from_worker, :to_worker, :message_type, :payload, :timestamp]
  defstruct [
    :message_id,
    :correlation_id,
    :from_worker,
    :to_worker,
    :message_type,
    :payload,
    :timestamp
  ]

  @spec new(map()) :: {:ok, __MODULE__} | {:error, term()}
  def new(params) do
    with {:ok, msg_id} <- validate_msg_id(params["message_id"]),
         {:ok, corr_id} <- validate_corr_id(params["correlation_id"]),
         {:ok, from} <- validate_worker(params["from_worker"]),
         {:ok, to} <- validate_worker(params["to_worker"]),
         {:ok, type} <- validate_type(params["message_type"]),
         {:ok, payload} <- validate_payload(params["payload"]),
         {:ok, timestamp} <- validate_timestamp(params["timestamp"]) do
      {:ok, %__MODULE__{
        message_id: msg_id,
        correlation_id: corr_id,
        from_worker: from,
        to_worker: to,
        message_type: type,
        payload: payload,
        timestamp: timestamp
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec to_json(__MODULE__) :: String.t()
  def to_json(envelope) do
    Jason.encode!(to_map(envelope))
  end

  @spec from_json(String.t()) :: {:ok, __MODULE__} | {:error, term()}
  def from_json(json_str) do
    case Jason.decode(json_str) do
      {:ok, map} -> from_map(map)
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @spec to_map(__MODULE__) :: map()
  def to_map(envelope) do
    %{
      message_id: envelope.message_id,
      correlation_id: envelope.correlation_id,
      from_worker: envelope.from_worker,
      to_worker: envelope.to_worker,
      message_type: envelope.message_type,
      payload: envelope.payload,
      timestamp: envelope.timestamp
    }
  end

  @spec from_map(map()) :: {:ok, __MODULE__} | {:error, term()}
  def from_map(map) do
    with {:ok, msg_id} <- validate_msg_id(map["message_id"] || map[:message_id]),
         {:ok, corr_id} <- validate_corr_id(map["correlation_id"] || map[:correlation_id]),
         {:ok, from} <- validate_worker(map["from_worker"] || map[:from_worker]),
         {:ok, to} <- validate_worker(map["to_worker"] || map[:to_worker]),
         {:ok, type} <- validate_type(map["message_type"] || map[:message_type]),
         {:ok, payload} <- validate_payload(map["payload"] || map[:payload]),
         {:ok, timestamp} <- validate_timestamp(map["timestamp"] || map[:timestamp]) do
      {:ok, %__MODULE__{
        message_id: msg_id,
        correlation_id: corr_id,
        from_worker: from,
        to_worker: to,
        message_type: type,
        payload: payload,
        timestamp: timestamp
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private validation functions

  defp validate_msg_id(id) when is_binary(id) and byte_size(id) > 0, do: {:ok, id}
  defp validate_msg_id(_), do: {:error, {:invalid_field, :message_id}}

  defp validate_corr_id(id) when is_binary(id) and byte_size(id) > 0, do: {:ok, id}
  defp validate_corr_id(_), do: {:error, {:invalid_field, :correlation_id}}

  defp validate_worker(worker) when is_binary(worker) and worker in ["qwen", "nemo", "router", "bus"] do
    {:ok, worker}
  end
  defp validate_worker(_), do: {:error, {:invalid_field, :worker}}

  defp validate_type(type) when type in [:task_assign, :task_accept, :task_result, :task_failed, :worker_heartbeat, :worker_status,
                                         "task_assign", "task_accept", "task_result", "task_failed", "worker_heartbeat", "worker_status"] do
    {:ok, if(is_binary(type), do: String.to_atom(type), else: type)}
  end
  defp validate_type(_), do: {:error, {:invalid_field, :message_type}}

  defp validate_payload(payload) when is_map(payload), do: {:ok, payload}
  defp validate_payload(_), do: {:error, {:invalid_field, :payload}}

  defp validate_timestamp(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, datetime, _} -> {:ok, datetime}
      :error -> {:error, {:invalid_field, :timestamp}}
    end
  end
  defp validate_timestamp(%DateTime{} = dt), do: {:ok, dt}
  defp validate_timestamp(_), do: {:error, {:invalid_field, :timestamp}}
end
