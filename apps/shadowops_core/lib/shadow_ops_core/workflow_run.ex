defmodule ShadowOpsCore.WorkflowRun do
  @moduledoc "Persistent workflow execution lifecycle record."
  @derive Jason.Encoder
  @enforce_keys [:id, :workflow_id, :requested_by, :queued_at, :status]
  defstruct [
    :id,
    :workflow_id,
    :requested_by,
    :queued_at,
    :started_at,
    :finished_at,
    :status,
    :result,
    :exit_code,
    :audit_ref,
    :evidence_ref,
    :trigger,
    :node,
    :stdout_ref,
    :stderr_ref,
    :correlation_id
  ]
end
