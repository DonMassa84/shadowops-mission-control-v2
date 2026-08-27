defmodule ShadowOpsCore.WorkflowCuration do
  @moduledoc """
  Evidence-first curation for locally registered workflow candidates.

  Curation turns discovery records into a production-readiness funnel without granting
  execution. Metadata normalization, classification and conservative duplicate grouping
  may happen automatically; CONNECTED, TESTED and PRODUCTION_READY require explicit
  runtime/governance evidence on the underlying record and therefore fail closed.
  """

  alias ShadowOpsCore.{LocalWorkflowEvidenceStore, LocalWorkflowRegistry}

  @categories ~w(BUSINESS SECURITY CAREER DATA AI AGENT SYSTEM REPORTING)
  @terminal_statuses ~w(DISCOVERED NORMALIZED CONNECTED TESTED PRODUCTION_READY)
  @risk_levels ~w(L0 L1 L2 L3)

  @spec snapshot(map() | nil) :: map()
  def snapshot(registry \\ nil) do
    registry = registry || LocalWorkflowRegistry.snapshot()
    evidence = LocalWorkflowEvidenceStore.snapshot(registry)

    records =
      registry
      |> Map.get(:records, [])
      |> Enum.map(&apply_evidence(&1, Map.get(evidence, &1.id)))

    curated = Enum.map(records, &curate/1)
    duplicate_groups = duplicate_groups(curated)
    duplicate_ids = duplicate_id_set(duplicate_groups)

    curated =
      Enum.map(curated, fn record ->
        Map.put(record, :duplicate_candidate, MapSet.member?(duplicate_ids, record.id))
      end)

    unique_count =
      curated
      |> Enum.map(& &1.dedupe_key)
      |> MapSet.new()
      |> MapSet.size()

    %{
      id: "workflow-curation",
      kind: "workflow_curation",
      status: if(curated == [], do: "NOT_CONFIGURED", else: "AVAILABLE"),
      source_type: "LOCAL_WORKFLOW_CURATION",
      synthetic: false,
      real_data: curated != [],
      lifecycle: @terminal_statuses,
      categories: @categories,
      counts: %{
        found: length(curated),
        unique: unique_count,
        potential_duplicates: max(length(curated) - unique_count, 0),
        duplicate_groups: length(duplicate_groups),
        normalized: count_status_at_least(curated, "NORMALIZED"),
        connected: count_status_at_least(curated, "CONNECTED"),
        tested: count_status_at_least(curated, "TESTED"),
        production_ready: count_status_at_least(curated, "PRODUCTION_READY")
      },
      duplicate_groups: duplicate_groups,
      records: curated
    }
  end

  defp curate(record) do
    category = classify(record)
    risk = stronger_risk(infer_risk(record), Map.get(record, :risk_level))
    systems = required_systems(record)
    lifecycle_status = lifecycle_status(record)

    %{
      id: record.id,
      name: record.name,
      purpose: purpose(record),
      source: record.source,
      source_ref: record.source_ref,
      kind: record.kind,
      category: category,
      risk_level: risk,
      required_systems: systems,
      real_source_state: real_source_state(record),
      runtime_verified: record.runtime_verified == true,
      governance_mapped: record.governance_mapped == true,
      executable: record.executable == true,
      execution_tested: truthy?(record, :execution_tested),
      integration_mode: record.integration_mode,
      lifecycle_status: lifecycle_status,
      dedupe_key: dedupe_key(record, category),
      duplicate_candidate: false,
      production_ready: lifecycle_status == "PRODUCTION_READY",
      adapter: Map.get(record, :adapter),
      capability: Map.get(record, :capability),
      approval_required: Map.get(record, :approval_required, risk in ~w(L2 L3)),
      evidence_refs: Map.get(record, :evidence_refs, []),
      verified_at: Map.get(record, :verified_at),
      verified_by: Map.get(record, :verified_by)
    }
  end

  defp apply_evidence(record, nil), do: record

  defp apply_evidence(record, evidence) when is_map(evidence) do
    keys = [
      :runtime_verified,
      :real_data,
      :reachable,
      :execution_tested,
      :governance_mapped,
      :executable,
      :adapter,
      :capability,
      :risk_level,
      :approval_required,
      :evidence_refs,
      :verified_at,
      :verified_by
    ]

    Map.merge(record, Map.take(evidence, keys))
  end

  defp lifecycle_status(record) do
    connected =
      record.runtime_verified == true and record.real_data == true and record.reachable == true

    tested = connected and truthy?(record, :execution_tested)

    cond do
      tested and record.governance_mapped == true and record.executable == true ->
        "PRODUCTION_READY"

      tested ->
        "TESTED"

      connected ->
        "CONNECTED"

      normalized?(record) ->
        "NORMALIZED"

      true ->
        "DISCOVERED"
    end
  end

  defp normalized?(record) do
    is_binary(record.id) and record.id != "" and is_binary(record.name) and record.name != "" and
      is_binary(record.source_ref) and record.source_ref != ""
  end

  defp real_source_state(record) do
    cond do
      record.runtime_verified == true and record.real_data == true and record.reachable == true ->
        "CONNECTED"

      record.real_data == true ->
        "DISCOVERED_REAL_ARTIFACT"

      true ->
        "UNVERIFIED"
    end
  end

  defp classify(record) do
    lower = identity(record)

    cond do
      contains_any?(lower, ["career", "bewerb", "income", "job"]) ->
        "CAREER"

      contains_any?(lower, [
        "security",
        "audit",
        "policy",
        "governance",
        "zero-trust",
        "zero_trust"
      ]) ->
        "SECURITY"

      contains_any?(lower, ["report", "summary", "dashboard", "status", "health"]) ->
        "REPORTING"

      contains_any?(lower, ["agent", "assistant", "bot", "openclaw"]) ->
        "AGENT"

      contains_any?(lower, ["ai", "model", "llm", "rag", "research"]) ->
        "AI"

      contains_any?(lower, [
        "sync",
        "import",
        "export",
        "archive",
        "backup",
        "data",
        "document",
        "dokument"
      ]) ->
        "DATA"

      contains_any?(lower, [
        "mail",
        "gmail",
        "calendar",
        "github",
        "whatsapp",
        "telegram",
        "customer",
        "business"
      ]) ->
        "BUSINESS"

      true ->
        "SYSTEM"
    end
  end

  defp infer_risk(record) do
    lower = identity(record)

    cond do
      contains_any?(lower, [
        "deploy",
        "push",
        "delete",
        "cleanup",
        "stop",
        "restart",
        "shutdown",
        "safe-off",
        "send",
        "publish"
      ]) ->
        "L3"

      contains_any?(lower, [
        "write",
        "sync",
        "import",
        "export",
        "backup",
        "archive",
        "install",
        "update",
        "trigger"
      ]) ->
        "L2"

      contains_any?(lower, [
        "scan",
        "audit",
        "health",
        "status",
        "report",
        "read",
        "show",
        "list",
        "check"
      ]) ->
        "L0"

      record.kind in ["SYSTEMD_SERVICE", "SYSTEMD_TIMER"] ->
        "L2"

      true ->
        "L1"
    end
  end

  defp stronger_risk(inferred, explicit) when inferred in @risk_levels and explicit in @risk_levels do
    if risk_rank(explicit) > risk_rank(inferred), do: explicit, else: inferred
  end

  defp stronger_risk(inferred, _), do: inferred
  defp risk_rank(level), do: Enum.find_index(@risk_levels, &(&1 == level)) || 0

  defp required_systems(record) do
    lower = identity(record)

    []
    |> maybe_add(contains_any?(lower, ["gmail", "mail"]), "Gmail")
    |> maybe_add(String.contains?(lower, "calendar"), "Google Calendar")
    |> maybe_add(String.contains?(lower, "github"), "GitHub")
    |> maybe_add(String.contains?(lower, "whatsapp"), "WhatsApp")
    |> maybe_add(String.contains?(lower, "telegram"), "Telegram")
    |> maybe_add(contains_any?(lower, ["obsidian", "knowledge", "rag"]), "Knowledge")
    |> maybe_add(contains_any?(lower, ["i7", "node"]), "i7 Node")
    |> maybe_add(record.kind in ["SYSTEMD_SERVICE", "SYSTEMD_TIMER"], "systemd")
    |> maybe_add(record.kind == "GITHUB_ACTION", "GitHub Actions")
    |> Enum.reverse()
  end

  defp purpose(record) do
    record.name
    |> to_string()
    |> String.trim()
    |> case do
      "" -> "Unspecified local workflow"
      name -> name
    end
  end

  defp dedupe_key(record, category) do
    stem =
      record.name
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/\b(copy|backup|old|legacy|v\d+|v\d+\.\d+)\b/, " ")
      |> String.replace(~r/[^a-z0-9]+/, " ")
      |> String.split(" ", trim: true)
      |> Enum.reject(&(&1 in ["workflow", "service", "timer", "script", "job"]))
      |> Enum.join("-")

    family = kind_family(record.kind)
    "#{category}:#{family}:#{stem}"
  end

  defp kind_family(kind) when kind in ["SYSTEMD_SERVICE", "SYSTEMD_TIMER"],
    do: "SCHEDULED_RUNTIME"

  defp kind_family("GITHUB_ACTION"), do: "EXTERNAL_CI"
  defp kind_family(_), do: "LOCAL_WORKFLOW"

  defp duplicate_groups(records) do
    records
    |> Enum.group_by(& &1.dedupe_key)
    |> Enum.filter(fn {_key, rows} -> length(rows) > 1 end)
    |> Enum.map(fn {key, rows} ->
      %{
        key: key,
        count: length(rows),
        ids: rows |> Enum.map(& &1.id) |> Enum.sort(),
        names: rows |> Enum.map(& &1.name) |> Enum.uniq() |> Enum.sort()
      }
    end)
    |> Enum.sort_by(& &1.key)
  end

  defp duplicate_id_set(groups) do
    groups
    |> Enum.flat_map(& &1.ids)
    |> MapSet.new()
  end

  defp count_status_at_least(records, status) do
    minimum = status_rank(status)
    Enum.count(records, &(status_rank(&1.lifecycle_status) >= minimum))
  end

  defp status_rank(status), do: Enum.find_index(@terminal_statuses, &(&1 == status)) || 0

  defp truthy?(record, key), do: Map.get(record, key, false) == true

  defp identity(record) do
    [record.name, record.source, record.source_ref, record.kind, Map.get(record, :domain)]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(" ", &to_string/1)
    |> String.downcase()
  end

  defp contains_any?(value, needles), do: Enum.any?(needles, &String.contains?(value, &1))
  defp maybe_add(list, true, value), do: [value | list]
  defp maybe_add(list, false, _value), do: list
end
