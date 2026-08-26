defmodule ShadowOpsCore.DailyControl do
  @moduledoc """
  Read-only One-Click Daily Control workflow (shadowops.daily_control).

  Composes existing ShadowOps runtime sources into a single daily situation
  assessment and a deterministic Top-3 action list. Pure projection: no
  runtime mutation, no external action, no message send, no deployment.

  IO ONCE, then pure:
  The web layer (controller/LiveView) fetches the aggregated runtime overview
  and the IHK project domain snapshot, then `build/2` is a pure function
  over those inputs. Both API and UI use the exact same projection.
  """

  @workflow_id "shadowops.daily_control"
  @stale_backup_hours 26

  @type check :: %{
          domain: String.t(),
          status: String.t(),
          summary: String.t(),
          severity: String.t(),
          evidence: list(),
          action: list()
        }

  @type action :: %{
          rank: non_neg_integer,
          id: String.t(),
          domain: String.t(),
          title: String.t(),
          reason: String.t(),
          severity: String.t(),
          score: float(),
          evidence: list()
        }

  @doc """
  Pure projection from an already-fetched overview and IHK domain snapshot.

  Never performs IO. The web layer is responsible for the single fetch of
  all sources and passing them in, so every check and action is derived
  from one consistent read.

  The overview map must contain:
  - `:system` - ConnectorState from RuntimeSources.system/0
  - `:security` - map from SecurityStatus.check/0 (has `:overall`, `:checks`, `:synthetic`)
  - `:services` - ConnectorState from RuntimeSources.services/0
  - `:backups` - ConnectorState from RuntimeSources.backups/0
  - `:approvals` - list from ApprovalStore.list/0
  - `:runs` - list from RunStore.list/0
  - `:career` - ConnectorState from RuntimeSources.career/0
  - `:evidence` - map from RuntimeSources.evidence/0

  The ihk_domain map is from ProjectDomains.snapshot(:ihk).
  """
  @spec build(map(), map()) :: map()
  def build(overview, ihk_domain) when is_map(overview) and is_map(ihk_domain) do
    checks = [
      assess_system(overview),
      assess_security(overview),
      assess_services(overview),
      assess_backups(overview),
      assess_approvals(overview),
      assess_failed_runs(overview),
      assess_career(overview),
      assess_ihk(ihk_domain),
      assess_evidence(overview)
    ]

    attention_required = Enum.any?(checks, &(Map.get(&1, :status) != "GREEN"))
    overall_status = overall_status(checks)
    severity = worst_severity(checks)
    actions = rank_actions(checks)
    evidence = collect_evidence(checks)

    %{
      workflow_id: @workflow_id,
      status: overall_status,
      severity: severity,
      summary: summary_text(overall_status, checks),
      attention_required: attention_required,
      checks: checks,
      top_actions: actions,
      evidence: evidence,
      source_status: source_statuses(overview, ihk_domain),
      synthetic: false,
      generated_at: DateTime.utc_now()
    }
  end

  # --- domain assessors (fail-closed) ---

  defp assess_system(overview) do
    source = Map.get(overview, :system, %{})
    status = connector_status(source, "UNAVAILABLE")
    meta = Map.get(source, :metadata, %{})
    cpu = Map.get(meta, :cpu)
    memory = Map.get(meta, :ram)
    disk = Map.get(meta, :disk)
    synthetic = Map.get(source, :synthetic, false)

    {check_status, severity} = classify_system(status, cpu, memory, disk, synthetic)

    %{
      domain: "SYSTEM",
      status: check_status,
      severity: severity,
      summary: "System: #{status}",
      evidence:
        build_evidence("system", [
          {"status", status},
          {"cpu", cpu},
          {"memory", memory},
          {"disk", disk}
        ]),
      action: []
    }
  end

  defp classify_system("READY", cpu, memory, disk, false) do
    if numeric_ok?(cpu) and numeric_ok?(memory) and numeric_ok?(disk),
      do: {"GREEN", "INFO"},
      else: {"ATTENTION", "MEDIUM"}
  end

  defp classify_system(status, _cpu, _memory, _disk, _synthetic)
       when status in ["DEGRADED", "WARNING"],
       do: {"ATTENTION", "MEDIUM"}

  defp classify_system(_status, cpu, memory, disk, _synthetic)
       when not is_nil(cpu) or not is_nil(memory) or not is_nil(disk),
       do: {"ATTENTION", "MEDIUM"}

  defp classify_system(status, _cpu, _memory, _disk, true)
       when status in ["ERROR", "UNAVAILABLE", "NOT_CONFIGURED"],
       do: {"BLOCKED", "HIGH"}

  defp classify_system(_status, _cpu, _memory, _disk, true), do: {"BLOCKED", "HIGH"}
  defp classify_system(_status, _cpu, _memory, _disk, _synthetic), do: {"UNAVAILABLE", "MEDIUM"}

  defp assess_security(overview) do
    source = Map.get(overview, :security, %{})
    overall = Map.get(source, :overall, "UNKNOWN")
    status = Map.get(source, :status, "UNAVAILABLE")
    checks_map = Map.get(source, :checks, %{})
    synthetic = Map.get(source, :synthetic, false)

    {check_status, severity, action} =
      cond do
        overall == "PASS" and not synthetic ->
          {"GREEN", "INFO", []}

        overall == "FAIL" and status == "DEGRADED" ->
          {"ATTENTION", "HIGH",
           [
             make_action(
               "security-review",
               "SECURITY",
               "Security-Checks reparieren",
               "HIGH",
               build_evidence("security", [{"overall", overall}, {"status", status}]),
               %{
                 impact: 5,
                 urgency: 5,
                 success_probability: 0.9,
                 strategic_alignment: 0.9,
                 evidence_confidence: 0.95,
                 effort: 2
               }
             )
           ]}

        overall == "FAIL" or synthetic ->
          {"BLOCKED", "CRITICAL",
           [
             make_action(
               "security-review",
               "SECURITY",
               "Security-Status untersuchen",
               "CRITICAL",
               build_evidence("security", [{"overall", overall}, {"synthetic", synthetic}]),
               %{
                 impact: 5,
                 urgency: 5,
                 success_probability: 0.8,
                 strategic_alignment: 0.9,
                 evidence_confidence: 0.6,
                 effort: 3
               }
             )
           ]}

        true ->
          {"UNAVAILABLE", "MEDIUM", []}
      end

    %{
      domain: "SECURITY",
      status: check_status,
      severity: severity,
      summary: "Security: #{overall} (#{map_size(checks_map)} checks)",
      evidence: build_evidence("security", [{"overall", overall}, {"status", status}]),
      action: action
    }
  end

  defp assess_services(overview) do
    source = Map.get(overview, :services, %{})
    status = connector_status(source, "UNAVAILABLE")
    services = Map.get(source, :services, [])
    unhealthy = Enum.reject(services, &(&1["status"] in ["active", "running", "READY"]))
    unhealthy_count = length(unhealthy)
    synthetic = Map.get(source, :synthetic, false)

    {check_status, severity, action} =
      cond do
        status == "READY" and unhealthy_count == 0 and not synthetic ->
          {"GREEN", "INFO", []}

        unhealthy_count > 0 ->
          {"ATTENTION", "MEDIUM",
           [
             make_action(
               "service-recovery",
               "SERVICES",
               "Beeinträchtigte Dienste prüfen (#{unhealthy_count})",
               "MEDIUM",
               build_evidence("services", [{"status", status}, {"unhealthy", unhealthy_count}]),
               %{
                 impact: 3,
                 urgency: 3,
                 success_probability: 0.8,
                 strategic_alignment: 0.7,
                 evidence_confidence: 0.85,
                 effort: 2
               }
             )
           ]}

        true ->
          {"UNAVAILABLE", "MEDIUM", []}
      end

    %{
      domain: "SERVICES",
      status: check_status,
      severity: severity,
      summary: "Services: #{status} (#{unhealthy_count} unhealthy)",
      evidence: build_evidence("services", [{"status", status}, {"unhealthy", unhealthy_count}]),
      action: action
    }
  end

  defp assess_backups(overview) do
    source = Map.get(overview, :backups, %{})
    status = connector_status(source, "UNAVAILABLE")
    last_success = Map.get(source, :last_success_at)
    stale = stale?(last_success)
    synthetic = Map.get(source, :synthetic, false)

    {check_status, severity, action} =
      cond do
        status == "READY" and not stale and not synthetic ->
          {"GREEN", "INFO", []}

        status in ["NOT_CONNECTED", "UNAVAILABLE", "ERROR"] or stale or synthetic ->
          {"ATTENTION", "HIGH",
           [
             make_action(
               "backup-verify",
               "BACKUPS",
               "Backup-Lage verifizieren (fehlend/veraltet)",
               "HIGH",
               build_evidence("backups", [{"status", status}, {"stale", stale}]),
               %{
                 impact: 4,
                 urgency: 3,
                 success_probability: 0.8,
                 strategic_alignment: 0.8,
                 evidence_confidence: 0.85,
                 effort: 2
               }
             )
           ]}

        true ->
          {"UNAVAILABLE", "MEDIUM", []}
      end

    %{
      domain: "BACKUPS",
      status: check_status,
      severity: severity,
      summary: "Backups: #{status}#{if stale, do: " (veraltet)", else: ""}",
      evidence: build_evidence("backups", [{"status", status}, {"stale", stale}]),
      action: action
    }
  end

  defp assess_approvals(overview) do
    approvals = Map.get(overview, :approvals, [])
    pending = Enum.filter(approvals, &(&1.status in ["PENDING", "REQUESTED"]))
    pending_count = length(pending)

    {check_status, severity, action} =
      cond do
        pending_count == 0 ->
          {"GREEN", "INFO", []}

        pending_count > 0 ->
          {"ATTENTION", "MEDIUM",
           [
             make_action(
               "approval-clear",
               "APPROVALS",
               "#{pending_count} offene Freigaben bearbeiten",
               "MEDIUM",
               build_evidence("approvals", [{"pending", pending_count}]),
               %{
                 impact: 2,
                 urgency: 3,
                 success_probability: 0.9,
                 strategic_alignment: 0.6,
                 evidence_confidence: 0.9,
                 effort: 1
               }
             )
           ]}

        true ->
          {"UNAVAILABLE", "LOW", []}
      end

    %{
      domain: "APPROVALS",
      status: check_status,
      severity: severity,
      summary:
        "Approvals: #{if pending_count > 0, do: "ATTENTION", else: "OK"} (#{pending_count} pending)",
      evidence: build_evidence("approvals", [{"pending", pending_count}]),
      action: action
    }
  end

  defp assess_failed_runs(overview) do
    runs = Map.get(overview, :runs, [])
    failed = Enum.filter(runs, &(&1.status in ["FAILED", "ERROR", "ABORTED"]))
    failed_count = length(failed)

    {check_status, severity, action} =
      cond do
        failed_count == 0 ->
          {"GREEN", "INFO", []}

        failed_count > 0 ->
          {"ATTENTION", "HIGH",
           [
             make_action(
               "failed-run-recover",
               "FAILED_RUNS",
               "#{failed_count} fehlgeschlagene Workflow-Runs untersuchen",
               "HIGH",
               build_evidence("failed_runs", [{"failed", failed_count}]),
               %{
                 impact: 4,
                 urgency: 4,
                 success_probability: 0.85,
                 strategic_alignment: 0.8,
                 evidence_confidence: 0.9,
                 effort: 3
               }
             )
           ]}

        true ->
          {"UNAVAILABLE", "MEDIUM", []}
      end

    %{
      domain: "FAILED_RUNS",
      status: check_status,
      severity: severity,
      summary:
        "Runs: #{if failed_count > 0, do: "ATTENTION", else: "OK"} (#{failed_count} failed)",
      evidence: build_evidence("failed_runs", [{"failed", failed_count}]),
      action: action
    }
  end

  defp assess_career(overview) do
    source = Map.get(overview, :career, %{})
    status = connector_status(source, "UNAVAILABLE")
    meta = Map.get(source, :metadata, %{})
    ihk = Map.get(meta, :ihk_workflow, %{})
    ihk_status = Map.get(ihk, :status, "UNKNOWN")
    synthetic = Map.get(source, :synthetic, false)

    {check_status, severity} =
      cond do
        status == "READY" and not synthetic ->
          {"GREEN", "INFO"}

        status in ["NOT_CONFIGURED", "UNAVAILABLE", "ERROR"] ->
          {"ATTENTION", "LOW"}

        status == "DEGRADED" ->
          {"ATTENTION", "MEDIUM"}

        true ->
          {"UNAVAILABLE", "MEDIUM"}
      end

    %{
      domain: "CAREER",
      status: check_status,
      severity: severity,
      summary: "Career: #{status} (IHK: #{ihk_status})",
      evidence: build_evidence("career", [{"status", status}, {"ihk_workflow", ihk_status}]),
      action: []
    }
  end

  defp assess_ihk(ihk_domain) do
    status = Map.get(ihk_domain, :status, "UNAVAILABLE")
    real_data = Map.get(ihk_domain, :real_data, false)
    error_code = Map.get(ihk_domain, :error_code)

    {check_status, severity, action} =
      cond do
        status == "READY" and real_data and is_nil(error_code) ->
          {"GREEN", "INFO", []}

        status == "READY" and not real_data ->
          {"ATTENTION", "MEDIUM",
           [
             make_action(
               "ihk-evidence",
               "IHK",
               "IHK/BA Evidenz vorhanden aber nicht verifiziert",
               "MEDIUM",
               build_evidence("ihk", [{"status", status}, {"real_data", real_data}]),
               %{
                 impact: 2,
                 urgency: 2,
                 success_probability: 0.7,
                 strategic_alignment: 0.8,
                 evidence_confidence: 0.6,
                 effort: 1
               }
             )
           ]}

        status in ["NOT_CONFIGURED", "UNAVAILABLE"] or error_code ->
          {"ATTENTION", "MEDIUM",
           [
             make_action(
               "ihk-evidence",
               "IHK",
               "IHK/BA Evidenz-Domain nicht verfügbar",
               "MEDIUM",
               build_evidence("ihk", [{"status", status}, {"error", error_code}]),
               %{
                 impact: 2,
                 urgency: 2,
                 success_probability: 0.7,
                 strategic_alignment: 0.8,
                 evidence_confidence: 0.5,
                 effort: 1
               }
             )
           ]}

        true ->
          {"UNAVAILABLE", "MEDIUM", []}
      end

    %{
      domain: "IHK",
      status: check_status,
      severity: severity,
      summary: "IHK/BA: #{status}",
      evidence: build_evidence("ihk", [{"status", status}, {"real_data", real_data}]),
      action: action
    }
  end

  defp assess_evidence(overview) do
    source = Map.get(overview, :evidence, %{})
    availability = Map.get(source, :availability, "UNAVAILABLE")
    artifacts = Map.get(source, :artifacts, [])
    artifact_count = length(artifacts)

    {check_status, severity} =
      cond do
        availability == "AVAILABLE" and artifact_count > 0 ->
          {"GREEN", "INFO"}

        availability == "UNAVAILABLE" ->
          {"BLOCKED", "MEDIUM"}

        artifact_count == 0 ->
          {"ATTENTION", "LOW"}

        true ->
          {"ATTENTION", "LOW"}
      end

    %{
      domain: "EVIDENCE",
      status: check_status,
      severity: severity,
      summary: "Evidence: #{availability} (#{artifact_count} artifacts)",
      evidence:
        build_evidence("evidence", [{"availability", availability}, {"artifacts", artifact_count}]),
      action: []
    }
  end

  # --- action ranking (deterministic, no LLM) ---

  defp make_action(id, domain, title, severity, evidence, weights) do
    %{
      id: id,
      domain: domain,
      title: title,
      reason: title,
      severity: severity,
      evidence: evidence,
      impact: Map.get(weights, :impact, 1),
      urgency: Map.get(weights, :urgency, 1),
      success_probability: Map.get(weights, :success_probability, 0.5),
      strategic_alignment: Map.get(weights, :strategic_alignment, 0.5),
      evidence_confidence: Map.get(weights, :evidence_confidence, 0.5),
      effort: Map.get(weights, :effort, 1)
    }
  end

  defp compute_score(candidate) do
    impact = Map.get(candidate, :impact, 1)
    urgency = Map.get(candidate, :urgency, 1)
    success = Map.get(candidate, :success_probability, 0.5)
    align = Map.get(candidate, :strategic_alignment, 0.5)
    conf = Map.get(candidate, :evidence_confidence, 0.5)
    effort = max(Map.get(candidate, :effort, 1), 1)
    impact * urgency * success * align * conf / effort
  end

  defp rank_actions(checks) do
    candidates =
      checks
      |> Enum.flat_map(&Map.get(&1, :action, []))
      |> Enum.map(fn c -> Map.put(c, :score, compute_score(c)) end)

    scored =
      Enum.sort_by(candidates, fn c ->
        {-Map.get(c, :score), severity_rank(Map.get(c, :severity)), Map.get(c, :domain)}
      end)

    scored
    |> Enum.with_index(1)
    |> Enum.map(fn {c, index} ->
      %{
        rank: index,
        id: Map.get(c, :id),
        domain: Map.get(c, :domain),
        title: Map.get(c, :title),
        reason: Map.get(c, :reason),
        severity: Map.get(c, :severity),
        score: Map.get(c, :score),
        evidence: Map.get(c, :evidence, [])
      }
    end)
    |> Enum.take(3)
  end

  # --- helpers ---

  defp connector_status(source, default) when is_map(source) do
    Map.get(source, :status, default)
  end

  defp connector_status(_, default), do: default

  defp numeric_ok?(nil), do: false
  defp numeric_ok?(value) when is_number(value), do: value < 90
  defp numeric_ok?(_), do: false

  defp stale?(nil), do: true

  defp stale?(%DateTime{} = last) do
    DateTime.diff(DateTime.utc_now(), last, :hour) > @stale_backup_hours
  end

  defp stale?(_), do: true

  defp build_evidence(domain, pairs) when is_list(pairs) do
    Enum.map(pairs, fn {key, value} ->
      %{domain: to_string(domain), key: to_string(key), value: inspect(value)}
    end)
  end

  defp severity_rank("CRITICAL"), do: 4
  defp severity_rank("HIGH"), do: 3
  defp severity_rank("MEDIUM"), do: 2
  defp severity_rank("LOW"), do: 1
  defp severity_rank(_), do: 0

  defp overall_status(checks) do
    statuses = Enum.map(checks, &Map.get(&1, :status))

    cond do
      Enum.all?(statuses, &(&1 == "GREEN")) -> "GREEN"
      Enum.any?(statuses, &(&1 == "UNAVAILABLE")) -> "UNAVAILABLE"
      Enum.any?(statuses, &(&1 == "BLOCKED")) -> "BLOCKED"
      true -> "ATTENTION"
    end
  end

  defp worst_severity(checks) do
    checks
    |> Enum.map(&severity_rank(Map.get(&1, :severity)))
    |> Enum.max(fn -> 0 end)
    |> case do
      4 -> "CRITICAL"
      3 -> "HIGH"
      2 -> "MEDIUM"
      1 -> "LOW"
      _ -> "INFO"
    end
  end

  defp collect_evidence(checks) do
    checks
    |> Enum.flat_map(&Map.get(&1, :evidence, []))
    |> Enum.take(50)
  end

  defp source_statuses(overview, ihk_domain) do
    domains = [
      {"SYSTEM", Map.get(overview, :system, %{})},
      {"SECURITY", Map.get(overview, :security, %{})},
      {"SERVICES", Map.get(overview, :services, %{})},
      {"BACKUPS", Map.get(overview, :backups, %{})},
      {"APPROVALS", %{}},
      {"FAILED_RUNS", %{}},
      {"CAREER", Map.get(overview, :career, %{})},
      {"EVIDENCE", Map.get(overview, :evidence, %{})},
      {"IHK", ihk_domain}
    ]

    Enum.map(domains, fn {name, source} ->
      %{
        domain: name,
        status: connector_status(source, "UNAVAILABLE"),
        available:
          connector_status(source, "UNAVAILABLE") not in [
            "UNAVAILABLE",
            "NOT_CONFIGURED",
            "ERROR"
          ],
        synthetic: Map.get(source, :synthetic, false)
      }
    end)
  end

  defp summary_text("GREEN", _checks), do: "Alle geprüften Bereiche sind im grünen Bereich."

  defp summary_text(status, checks) do
    attention =
      checks
      |> Enum.reject(&(Map.get(&1, :status) == "GREEN"))
      |> Enum.map_join(", ", &Map.get(&1, :domain))

    "Status #{status}. Aufmerksamkeit erforderlich in: #{attention}."
  end
end
