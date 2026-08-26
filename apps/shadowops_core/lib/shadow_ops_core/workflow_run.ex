defmodule ShadowOpsCore.WorkflowRun do
  @moduledoc "Persistent execution lifecycle record for workflows and governed service actions."
  @derive Jason.Encoder
  @enforce_keys [:id, :workflow_id, :requested_by, :queued_at, :status]
  defstruct [
    :id,
    :workflow_id,
    :kind,
    :resource_id,
    :action,
    :requested_by,
    :queued_at,
    :started_at,
    :finished_at,
    :duration_ms,
    :status,
    :result,
    :exit_code,
    :score,
    :evaluation,
    :before_state,
    :after_state,
    :audit_ref,
    :evidence_ref,
    :trigger,
    :node,
    :stdout_ref,
    :stderr_ref,
    :correlation_id
  ]
end
