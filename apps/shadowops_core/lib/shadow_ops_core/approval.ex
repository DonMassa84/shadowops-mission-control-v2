defmodule ShadowOpsCore.Approval do
  @moduledoc "Durable approval record with explicit immutable decision states."
  alias ShadowOpsCore.{Correlation, RiskPolicy}
  @derive Jason.Encoder
  @enforce_keys [
    :id,
    :requested_at,
    :requested_by,
    :action,
    :resource,
    :reason,
    :status,
    :expires_at,
    :risk,
    :correlation_id
  ]
  defstruct [
    :id,
    :requested_at,
    :requested_by,
    :action,
    :resource,
    :reason,
    :status,
    :decision_at,
    :decided_by,
    :audit_ref,
    :expires_at,
    :risk,
    :correlation_id,
    :evidence_ref
  ]

  def new(attrs) do
    now = DateTime.utc_now()

    with requested_by when is_binary(requested_by) and requested_by != "" <-
           value(attrs, :requested_by) || value(attrs, :actor),
         action when is_binary(action) and action != "" <- value(attrs, :action),
         resource when is_binary(resource) and resource != "" <- value(attrs, :resource),
         {:ok, requested_at} <- datetime(value(attrs, :requested_at), now),
         {:ok, expires_at} <-
           datetime(value(attrs, :expires_at), DateTime.add(now, 86_400, :second)),
         risk when risk in ~w(L0 L1 L2 L3) <-
           value(attrs, :risk) || RiskPolicy.infer_risk(action),
         {:ok, correlation_id} <- Correlation.ensure(value(attrs, :correlation_id)) do
      {:ok,
       %__MODULE__{
         id: value(attrs, :id) || "approval_" <> random_id(),
         requested_at: requested_at,
         requested_by: requested_by,
         action: action,
         resource: resource,
         reason: value(attrs, :reason) || "unspecified",
         status: "PENDING",
         expires_at: expires_at,
         risk: risk,
         correlation_id: correlation_id,
         evidence_ref: value(attrs, :evidence_ref)
       }}
    else
      _ -> {:error, :invalid_approval}
    end
  end

  def decide(%__MODULE__{status: "PENDING"} = approval, decision, actor)
      when decision in ["APPROVED", "REJECTED"] and is_binary(actor) and actor != "" do
    if expired?(approval),
      do: {:error, :expired},
      else:
        {:ok, %{approval | status: decision, decision_at: DateTime.utc_now(), decided_by: actor}}
  end

  def decide(%__MODULE__{status: status}, _decision, _actor),
    do: {:error, {:invalid_transition, status}}

  def evaluate(%__MODULE__{} = approval, action, resource, risk \\ nil) do
    cond do
      expired?(approval) -> {:blocked, :expired}
      approval.status != "APPROVED" -> {:blocked, {:approval_status, approval.status}}
      approval.action != action -> {:blocked, :wrong_action}
      approval.resource != resource -> {:blocked, :wrong_resource}
      is_binary(risk) and approval.risk != risk -> {:blocked, :wrong_risk}
      true -> :allowed
    end
  end

  def expired?(%__MODULE__{expires_at: expires_at}),
    do: DateTime.compare(DateTime.utc_now(), expires_at) != :lt

  defp random_id, do: :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp datetime(nil, default), do: {:ok, default}
  defp datetime(%DateTime{} = value, _default), do: {:ok, value}

  defp datetime(value, _default) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> {:error, :invalid_datetime}
    end
  end

  defp datetime(_value, _default), do: {:error, :invalid_datetime}
end
