defmodule AgentRuntime.TaskEnvelope do
  @moduledoc """
  Task envelope for headless CommunicationBus flow between Qwen (RTX 3060) and Nemo (i7/GTX 1050 Ti).
  
  Communication path: Qwen -> CommunicationBus -> LocalQueue/Router -> Nemo/i7 -> TASK_ACCEPT -> NEMO_ACK_OK -> CommunicationBus -> Qwen
  
  Status display: QWEN=BUSY, NEMO=AVAILABLE, TASK=58-3, CHANNEL=LOCAL_QUEUE, STATUS=RUNNING
  DISPLAY_DEPENDENCY=0, MAX_ACTIVE_TESTS=1
  """

  @type task_id :: String.t()
  @type worker_id :: String.t()
  @type channel :: :local_queue | :communication_bus
  @type status :: :pending | :accepted | :running | :completed | :failed

  @enforce_keys [:task_id, :source_worker, :target_worker, :payload, :channel]
  defstruct [
    :task_id,
    :source_worker,
    :target_worker,
    :payload,
    :channel,
    :status,
    :created_at,
    :accepted_at,
    :completed_at,
    :evidence
  ]

  @spec new(map()) :: {:ok, __MODULE__} | {:error, term()}
  def new(params) do
    with {:ok, task_id} <- validate_task_id(params["task_id"]),
         {:ok, source} <- validate_worker(params["source_worker"]),
         {:ok, target} <- validate_worker(params["target_worker"]),
         {:ok, payload} <- validate_payload(params["payload"]),
         {:ok, channel} <- validate_channel(params["channel"]) do
      {:ok, %__MODULE__{
        task_id: task_id,
        source_worker: source,
        target_worker: target,
        payload: payload,
        channel: channel,
        status: :pending,
        created_at: DateTime.utc_now(),
        accepted_at: nil,
        completed_at: nil,
        evidence: %{}
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec accept(__MODULE__) :: {:ok, __MODULE__} | {:error, term()}
  def accept(envelope) do
    if envelope.status == :pending do
      {:ok, Map.put(envelope, :status, :accepted) |> Map.put(:accepted_at, DateTime.utc_now())}
    else
      {:error, {:invalid_state, envelope.status}}
    end
  end

  @spec start(__MODULE__) :: {:ok, __MODULE__} | {:error, term()}
  def start(envelope) do
    if envelope.status == :accepted do
      {:ok, Map.put(envelope, :status, :running)}
    else
      {:error, {:invalid_state, envelope.status}}
    end
  end

  @spec complete(__MODULE__, map()) :: {:ok, __MODULE__} | {:error, term()}
  def complete(envelope, evidence) do
    if envelope.status == :running do
      {:ok, envelope
      |> Map.put(:status, :completed)
      |> Map.put(:completed_at, DateTime.utc_now())
      |> Map.put(:evidence, evidence)}
    else
      {:error, {:invalid_state, envelope.status}}
    end
  end

  @spec fail(__MODULE__, String.t()) :: {:ok, __MODULE__} | {:error, term()}
  def fail(envelope, reason) do
    if envelope.status in [:pending, :accepted, :running] do
      {:ok, envelope
      |> Map.put(:status, :failed)
      |> Map.put(:completed_at, DateTime.utc_now())
      |> Map.update(:evidence, %{failure_reason: reason}, fn e -> Map.put(e, :failure_reason, reason) end)}
    else
      {:error, {:invalid_state, envelope.status}}
    end
  end

  @spec status_display(__MODULE__) :: String.t()
  def status_display(envelope) do
    source_status = if envelope.source_worker == "qwen", do: "BUSY", else: "AVAILABLE"
    target_status = if envelope.target_worker == "nemo", do: "AVAILABLE", else: "BUSY"
    
    "QWEN=#{source_status} NEMO=#{target_status} TASK=#{envelope.task_id} CHANNEL=#{channel_to_str(envelope.channel)} STATUS=#{status_to_str(envelope.status)}"
  end

  @spec to_map(__MODULE__) :: map()
  def to_map(envelope) do
    %{
      task_id: envelope.task_id,
      source_worker: envelope.source_worker,
      target_worker: envelope.target_worker,
      payload: envelope.payload,
      channel: envelope.channel,
      status: envelope.status,
      created_at: envelope.created_at,
      accepted_at: envelope.accepted_at,
      completed_at: envelope.completed_at,
      evidence: envelope.evidence
    }
  end

  @spec from_map(map()) :: {:ok, __MODULE__} | {:error, term()}
  def from_map(map) do
    with {:ok, task_id} <- validate_task_id(map["task_id"] || map[:task_id]),
         {:ok, source} <- validate_worker(map["source_worker"] || map[:source_worker]),
         {:ok, target} <- validate_worker(map["target_worker"] || map[:target_worker]),
         {:ok, payload} <- validate_payload(map["payload"] || map[:payload]),
         {:ok, channel} <- validate_channel(map["channel"] || map[:channel]),
         {:ok, status} <- validate_status(map["status"] || map[:status]),
         {:ok, created_at} <- parse_datetime(map["created_at"] || map[:created_at]),
         {:ok, accepted_at} <- parse_optional_datetime(map["accepted_at"] || map[:accepted_at]),
         {:ok, completed_at} <- parse_optional_datetime(map["completed_at"] || map[:completed_at]),
         {:ok, evidence} <- validate_evidence(map["evidence"] || map[:evidence]) do
      {:ok, %__MODULE__{
        task_id: task_id,
        source_worker: source,
        target_worker: target,
        payload: payload,
        channel: channel,
        status: status,
        created_at: created_at,
        accepted_at: accepted_at,
        completed_at: completed_at,
        evidence: evidence
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private validation functions

  defp validate_task_id(id) when is_binary(id) and byte_size(id) > 0, do: {:ok, id}
  defp validate_task_id(_), do: {:error, {:invalid_field, :task_id}}

  defp validate_worker(worker) when is_binary(worker) and worker in ["qwen", "nemo"] do
    {:ok, worker}
  end
  defp validate_worker(_), do: {:error, {:invalid_field, :worker}}

  defp validate_payload(payload) when is_map(payload) do
    {:ok, payload}
  end
  defp validate_payload(_), do: {:error, {:invalid_field, :payload}}

  defp validate_channel(channel) when channel in [:local_queue, :communication_bus, "local_queue", "communication_bus"] do
    {:ok, if(is_binary(channel), do: String.to_atom(channel), else: channel)}
  end
  defp validate_channel(_), do: {:error, {:invalid_field, :channel}}

  defp validate_status(status) when status in [:pending, :accepted, :running, :completed, :failed, "pending", "accepted", "running", "completed", "failed"] do
    {:ok, if(is_binary(status), do: String.to_atom(status), else: status)}
  end
  defp validate_status(_), do: {:error, {:invalid_field, :status}}

  defp parse_datetime(dt) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, datetime, _} -> {:ok, datetime}
      :error -> {:error, {:invalid_field, :created_at}}
    end
  end
  defp parse_datetime(%DateTime{} = dt), do: {:ok, dt}
  defp parse_datetime(_), do: {:error, {:invalid_field, :created_at}}

  defp parse_optional_datetime(nil), do: {:ok, nil}
  defp parse_optional_datetime(dt), do: parse_datetime(dt)

  defp validate_evidence(evidence) when is_map(evidence), do: {:ok, evidence}
  defp validate_evidence(nil), do: {:ok, %{}}

  defp channel_to_str(:local_queue), do: "LOCAL_QUEUE"
  defp channel_to_str(:communication_bus), do: "COMMUNICATION_BUS"
  defp channel_to_str(str) when is_binary(str), do: String.upcase(str)

  defp status_to_str(:pending), do: "PENDING"
  defp status_to_str(:accepted), do: "ACCEPTED"
  defp status_to_str(:running), do: "RUNNING"
  defp status_to_str(:completed), do: "COMPLETED"
  defp status_to_str(:failed), do: "FAILED"
  defp status_to_str(str) when is_binary(str), do: String.upcase(str)
end
