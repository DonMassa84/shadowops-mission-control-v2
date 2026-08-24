defmodule ShadowOpsCore.Events do
  @moduledoc """
  Event publication for Health/Events stage.

  Events flow: ExecutionService -> Adapter -> Audit -> Health/Event publication
  """

  @doc """
  Publishes an event to the event bus.
  """
  def publish(event_module, event_type, actor, target, result, metadata \\ %{}) do
    case event_module.new(event_type, actor, target, result, metadata) do
      {:ok, event} ->
        # In production, this would publish to PubSub or message queue
        {:ok, event}

      error ->
        error
    end
  end

  @doc """
  Publishes a health event.
  """
  def publish_health(node_id, status, metadata \\ %{}) do
    {:ok, %{node_id: node_id, status: status, metadata: metadata, timestamp: DateTime.utc_now()}}
  end

  @doc """
  Publishes an execution event.
  """
  def publish_execution(workflow_id, event_type, result, metadata \\ %{}) do
    {:ok,
     %{
       workflow_id: workflow_id,
       event: event_type,
       result: result,
       metadata: metadata,
       timestamp: DateTime.utc_now()
     }}
  end
end
