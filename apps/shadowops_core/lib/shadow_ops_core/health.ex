defmodule ShadowOpsCore.Health do
  @moduledoc """
  Health status with UNKNOWN support.

  OpenClaw Health can be:
  - ACTIVE_SERVICE
  - HTTP_AVAILABLE
  - DEGRADED
  - OFFLINE
  - UNKNOWN
  """

  @statuses [:ok, :degraded, :unknown, :offline, :active_service, :http_available]

  @doc """
  Validates a health status.
  """
  def valid?(status) do
    status in @statuses
  end

  @doc """
  Returns default UNKNOWN health.
  """
  def unknown(reason \\ "no_probe") do
    {:ok, %{status: :unknown, reason: reason, checked_at: DateTime.utc_now()}}
  end

  @doc """
  Creates a health status.
  """
  def new(status, metadata \\ %{}) do
    if valid?(status) do
      {:ok, %{status: status, metadata: metadata, checked_at: DateTime.utc_now()}}
    else
      {:error, {:invalid_status, status}}
    end
  end

  @doc """
  Returns all valid statuses.
  """
  def statuses, do: @statuses
end
