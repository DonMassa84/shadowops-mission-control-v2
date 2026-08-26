defmodule ShadowOpsCore.ApprovalStore do
  @moduledoc "Append-only persistent approval event store."
  alias ShadowOpsCore.{Approval, Audit, Correlation, EventBus, RiskPolicy}
  @path Path.expand("../../../../var/approvals.jsonl", __DIR__)

  def path, do: Application.get_env(:shadowops_core, :approval_path, @path)

  def list,
    do:
      records()
      |> Map.values()
      |> Enum.map(&effective_status/1)
      |> Enum.sort_by(&DateTime.to_unix(&1.requested_at), :desc)

  def get(id) do
    case Map.fetch(records(), id) do
      {:ok, item} -> {:ok, effective_status(item)}
      :error -> {:error, :not_found}
    end
  end

  def create(attrs) do
    transact(fn ->
      with {:ok, approval} <- Approval.new(attrs),
           false <- Map.has_key?(records(), approval.id),
           {:ok, audit} <-
             Audit.record(
               :approval_requested,
               approval.requested_by,
               approval.resource,
               :success,
               %{
                 action: approval.action,
                 risk: approval.risk,
                 correlation_id: approval.correlation_id,
                 evidence_ref: approval.evidence_ref
               }
             ),
           record = %{approval | audit_ref: audit.id},
           :ok <- append(record),
           :ok <- publish("approval.requested", record) do
        {:ok, record}
      else
        true -> {:error, :already_exists}
        error -> error
      end
    end)
  end

  def approve(id, actor), do: decide(id, "APPROVED", actor)
  def reject(id, actor), do: decide(id, "REJECTED", actor)

  def validate(id, action, resource, risk_level),
    do:
      with(
        {:ok, approval} <- get(id),
        :allowed <- Approval.evaluate(approval, action, resource, risk_level),
        do: {:ok, approval}
      )

  def consume(id, action, resource, risk_level, actor)
      when is_binary(actor) and actor != "" do
    transact(fn ->
      with {:ok, current} <- get(id),
           :allowed <- Approval.evaluate(current, action, resource, risk_level),
           {:ok, consumed} <- Approval.consume(current, actor),
           {:ok, audit} <-
             Audit.record(:approval_consumed, actor, current.resource, :success, %{
               approval_id: id,
               action: current.action,
               risk: current.risk,
               correlation_id: current.correlation_id,
               evidence_ref: current.evidence_ref
             }),
           record = %{consumed | audit_ref: audit.id},
           :ok <- append(record),
           :ok <- publish("approval.consumed", record) do
        {:ok, record}
      else
        {:blocked, reason} -> {:blocked, reason}
        error -> error
      end
    end)
  end

  def consume(_id, _action, _resource, _risk_level, _actor),
    do: {:error, :valid_actor_required}

  defp decide(id, decision, actor) do
    transact(fn ->
      with {:ok, current} <- get(id),
           {:ok, decided} <- Approval.decide(current, decision, actor),
           event = if(decision == "APPROVED", do: :approval_granted, else: :approval_rejected),
           {:ok, audit} <-
             Audit.record(event, actor, current.resource, :success, %{
               approval_id: id,
               action: current.action,
               risk: current.risk,
               correlation_id: current.correlation_id,
               evidence_ref: current.evidence_ref
             }),
           record = %{decided | audit_ref: audit.id},
           :ok <- append(record),
           :ok <-
             publish(
               if(decision == "APPROVED", do: "approval.granted", else: "approval.rejected"),
               record
             ),
           do: {:ok, record}
    end)
  end

  defp records do
    case File.read(path()) do
      {:ok, body} ->
        body |> String.split("\n", trim: true) |> Enum.map(&decode/1) |> Map.new(&{&1.id, &1})

      {:error, :enoent} ->
        %{}

      {:error, reason} ->
        raise "approval store unreadable: #{inspect(reason)}"
    end
  end

  defp append(record) do
    File.mkdir_p!(Path.dirname(path()))

    case File.open(path(), [:append, :binary, :sync], fn file ->
           IO.binwrite(file, Jason.encode!(record) <> "\n")
         end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode(line) do
    row = Jason.decode!(line) |> canonical_defaults()
    fields = struct_fields(Approval)

    struct!(
      Approval,
      Map.new(row, fn {k, v} -> {Map.fetch!(fields, k), decode_time(k, v)} end)
    )
  end

  defp canonical_defaults(row) do
    risk =
      if row["risk"] in ~w(L0 L1 L2 L3),
        do: row["risk"],
        else: inferred_risk(row["action"])

    correlation_id =
      if Correlation.valid?(row["correlation_id"]),
        do: row["correlation_id"],
        else: deterministic_correlation(row["id"])

    row |> Map.put("risk", risk) |> Map.put("correlation_id", correlation_id)
  end

  defp inferred_risk(action) do
    case RiskPolicy.infer_risk(action) do
      risk when risk in ~w(L0 L1 L2 L3) -> risk
      _ -> "L3"
    end
  end

  defp deterministic_correlation(id) do
    digest = :crypto.hash(:sha256, "approval:" <> to_string(id)) |> Base.encode16(case: :lower)
    "corr_" <> String.slice(digest, 0, 32)
  end

  defp decode_time(key, value)
       when key in ["requested_at", "decision_at", "consumed_at", "expires_at"] and
              is_binary(value),
       do: elem(DateTime.from_iso8601(value), 1)

  defp decode_time(_key, value), do: value

  defp effective_status(%Approval{status: "PENDING"} = item),
    do: if(Approval.expired?(item), do: %{item | status: "EXPIRED"}, else: item)

  defp effective_status(item), do: item

  defp publish(type, approval) do
    case EventBus.publish(%{
           type: type,
           source: "shadowops",
           resource_id: "approval:" <> approval.id,
           correlation_id: approval.correlation_id,
           privacy: "metadata_only",
           synthetic: false,
           evidence_ref: approval.evidence_ref,
           metadata: %{action: approval.action, risk: approval.risk, status: approval.status}
         }) do
      {:ok, _event} -> :ok
      {:error, reason} -> {:error, {:approval_event_failed, reason}}
    end
  end

  defp transact(fun), do: :global.trans({{__MODULE__, path()}, self()}, fun)

  defp struct_fields(module) do
    module.__struct__()
    |> Map.delete(:__struct__)
    |> Map.keys()
    |> Map.new(&{Atom.to_string(&1), &1})
  end
end
