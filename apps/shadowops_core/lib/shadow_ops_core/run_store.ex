defmodule ShadowOpsCore.RunStore do
  @moduledoc "Append-only persistent store for real workflow execution lifecycles."
  alias ShadowOpsCore.{Audit, Correlation, WorkflowRun}
  @path Path.expand("../../../../var/runs.jsonl", __DIR__)

  def path, do: Application.get_env(:shadowops_core, :run_path, @path)
  def list, do: records() |> Map.values() |> Enum.sort_by(&DateTime.to_unix(&1.queued_at), :desc)

  def get(id) do
    case Map.fetch(records(), id) do
      {:ok, run} -> {:ok, run}
      :error -> {:error, :not_found}
    end
  end

  def queue(workflow_id, actor, attrs \\ %{}) do
    transact(fn ->
      with true <- workflow_exists?(workflow_id),
           true <- is_binary(actor) and actor != "",
           {:ok, correlation_id} <- Correlation.ensure(value(attrs, :correlation_id)),
           run = %WorkflowRun{
             id: value(attrs, :id) || "run_" <> random_id(),
             workflow_id: workflow_id,
             requested_by: actor,
             queued_at: DateTime.utc_now(),
             status: "QUEUED",
             evidence_ref: value(attrs, :evidence_ref),
             trigger: value(attrs, :trigger) || "api",
             node: value(attrs, :node) || "local-ryzen",
             stdout_ref: value(attrs, :stdout_ref),
             stderr_ref: value(attrs, :stderr_ref),
             correlation_id: correlation_id
           },
           false <- Map.has_key?(records(), run.id),
           {:ok, audit} <-
             Audit.record(:run_queued, actor, workflow_id, :success, %{
               run_id: run.id,
               evidence_ref: run.evidence_ref,
               correlation_id: run.correlation_id
             }),
           record = %{run | audit_ref: audit.id},
           :ok <- append(record) do
        {:ok, record}
      else
        false -> {:error, :invalid_workflow_or_actor}
        true -> {:error, :already_exists}
        error -> error
      end
    end)
  end

  def start(id, actor), do: transition(id, "RUNNING", actor, %{})

  def succeed(id, actor, result, exit_code \\ 0, evidence_ref \\ nil),
    do:
      transition(id, "SUCCESS", actor, %{
        result: result,
        exit_code: exit_code,
        evidence_ref: evidence_ref
      })

  def fail(id, actor, result, exit_code),
    do: transition(id, "FAILED", actor, %{result: result, exit_code: exit_code})

  def block(id, actor, result), do: transition(id, "BLOCKED", actor, %{result: result})

  defp transition(id, target, actor, attrs) do
    transact(fn ->
      with {:ok, current} <- get(id),
           :ok <- valid_transition(current.status, target),
           now = DateTime.utc_now(),
           event = if(target == "RUNNING", do: :run_started, else: :run_finished),
           audit_result = if(target in ["SUCCESS", "RUNNING"], do: :success, else: :blocked),
           {:ok, audit} <-
             Audit.record(event, actor, current.workflow_id, audit_result, %{
               run_id: id,
               status: target,
               evidence_ref: attrs[:evidence_ref],
               correlation_id: current.correlation_id
             }),
           record = apply_transition(current, target, now, attrs, audit.id),
           :ok <- append(record) do
        {:ok, record}
      end
    end)
  end

  defp valid_transition("QUEUED", "RUNNING"), do: :ok
  defp valid_transition("QUEUED", "BLOCKED"), do: :ok

  defp valid_transition("RUNNING", target) when target in ["SUCCESS", "FAILED", "BLOCKED"],
    do: :ok

  defp valid_transition(from, to), do: {:error, {:invalid_transition, from, to}}

  defp apply_transition(run, "RUNNING", now, _attrs, audit),
    do: %{run | status: "RUNNING", started_at: now, audit_ref: audit}

  defp apply_transition(run, target, now, attrs, audit),
    do: %{
      run
      | status: target,
        finished_at: now,
        result: attrs[:result],
        exit_code: attrs[:exit_code],
        evidence_ref: attrs[:evidence_ref] || run.evidence_ref,
        audit_ref: audit
    }

  defp workflow_exists?(id) do
    case YamlElixir.read_from_file!(Application.fetch_env!(:workflow_engine, :registry_path))[
           "workflows"
         ] do
      rows when is_list(rows) -> Enum.any?(rows, &(&1["id"] == id))
      rows when is_map(rows) -> Map.has_key?(rows, id)
      _ -> false
    end
  rescue
    _ -> false
  end

  defp records do
    case File.read(path()) do
      {:ok, body} ->
        body |> String.split("\n", trim: true) |> Enum.map(&decode/1) |> Map.new(&{&1.id, &1})

      {:error, :enoent} ->
        %{}

      {:error, reason} ->
        raise "run store unreadable: #{inspect(reason)}"
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
    row = Jason.decode!(line)

    row =
      if Correlation.valid?(row["correlation_id"]),
        do: row,
        else: Map.put(row, "correlation_id", deterministic_correlation(row["id"]))

    fields = struct_fields(WorkflowRun)

    struct!(
      WorkflowRun,
      Map.new(row, fn {k, v} -> {Map.fetch!(fields, k), decode_time(k, v)} end)
    )
  end

  defp decode_time(key, value)
       when key in ["queued_at", "started_at", "finished_at"] and is_binary(value),
       do: elem(DateTime.from_iso8601(value), 1)

  defp decode_time(_key, value), do: value
  defp random_id, do: :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)

  defp deterministic_correlation(id) do
    digest = :crypto.hash(:sha256, "run:" <> to_string(id)) |> Base.encode16(case: :lower)
    "corr_" <> String.slice(digest, 0, 32)
  end

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  defp transact(fun), do: :global.trans({{__MODULE__, path()}, self()}, fun)

  defp struct_fields(module) do
    module.__struct__()
    |> Map.delete(:__struct__)
    |> Map.keys()
    |> Map.new(&{Atom.to_string(&1), &1})
  end
end
