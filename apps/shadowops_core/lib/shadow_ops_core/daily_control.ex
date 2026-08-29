defmodule ShadowOpsCore.DailyControl do
  @moduledoc """
  Read-only One-Click Daily Control workflow (shadowops.daily_control).

  Composes existing ShadowOps runtime sources into a single daily situation
  assessment and a deterministic Top-3 action list. This is a pure projection:
  no runtime mutation, no external action, no message send, no deployment.

  IO ONCE, then pure:
  `snapshot/1` fetches the aggregated runtime overview (a single cached call
  in the web layer) and the IHK project domain snapshot, then `build/2` is a
  pure function over those inputs. Both the API controller and the LiveView
  reuse the exact same projection, so API and UI can never diverge.
  """

  @workflow_id "shadowops.daily_control"
  @stale_backup_hours 26

  # Fixed ranking weights (no LLM, no external scoring).
  @weights %{
    "security-review" => %{
      impact: 5,
      urgency: 5,
      success_probability: 0.9,
      strategic_alignment: 0.9,
      evidence_confidence: 0.95,
      effort: 2
    },
    "failed-run-recover" => %{
      impact: 4,
      urgency: 4,
      success_probability: 0.85,
      strategic_alignment: 0.8,
      evidence_confidence: 0.9,
      effort: 3
    },
    "backup-verify" => %{
      impact: 4,
      urgency: 3,
      success_probability: 0.8,
      strategic_alignment: 0.8,
      evidence_confidence: 0.85,
      effort: 2
    },
    "service-recovery" => %{
      impact: 3,
      urgency: 3,
      success_probability: 0.8,
      strategic_alignment: 0.7,
      evidence_confidence: 0.85,
      effort: 2
    },
    "approval-clear" => %{
      impact: 2,
      urgency: 3,
      success_probability: 0.9,
      strategic_alignment: 0.6,
      evidence_confidence: 0.9,
      effort: 1
    },
    "ihk-evidence" => %{
      impact: 2,
      urgency: 2,
      success_probability: 0.7,
      strategic_alignment: 0.8,
      evidence_confidence: 0.6,
      effort: 1
    }
  }

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
  Produces the canonical Daily Control snapshot.

  Options:
    - `:overview`    inject the aggregated overview map (for pure tests / web layer)
    - `:ihk_domain`  inject the ProjectDomains IHK snapshot map (for pure tests / web layer)
  """
  @spec snapshot(keyword()) :: map()
  def snapshot(opts \\ []) do
    overview = Keyword.get_lazy(opts, :overview, &default_overview/0)
    ihk_domain = Keyword.get_lazy(opts, :ihk_domain, &default_ihk/0)
    build(overview, ihk_domain)
  end

  @doc """
  Pure projection from an already-fetched overview and IHK domain snapshot.

  Never performs IO. The web layer is responsible for the single fetch of
  `ShadowOpsApi.overview()` and `ProjectDomains.snapshot(:ihk)` and passing
  them in, so every check and action is derived from one consistent read.
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
      summary: summary_text(overview, overall_status, checks),
      attention_required: attention_required,
      checks: checks,
      top_actions: actions,
      evidence: evidence,
      source_status: source_statuses(overview, ihk_domain),
      synthetic: false,
      generated_at: DateTime.utc_now()
    }
  end

  # --- IO helpers (core-only fallback; web layer injects the full overview) ---

  defp default_overview do
    %{
      system: ShadowOpsCore.RuntimeSources.system(),
      services: ShadowOpsCore.RuntimeSources.services(),
      backups: ShadowOpsCore.RuntimeSources.backups(),
      career: ShadowOpsCore.RuntimeSources.career(),
      evidence: ShadowOpsCore.RuntimeSources.evidence(),
      runs: %{status: "READY", records: ShadowOpsCore.RunStore.list()},
      approvals: %{status: "READY", records: ShadowOpsCore.ApprovalStore.list()},
      security: %{status: "UNAVAILABLE", synthetic: false, metadata: %{}}
    }
  end

  defp default_ihk, do: %{status: "UNAVAILABLE", records: [], synthetic: false}

  # --- domain assessors (fail-closed) ---

  defp assess_system(overview) do
    source = Map.get(overview, :system, %{})
    status = primary_status(source, "UNAVAILABLE")
    meta = Map.get(source, :metadata, %{})
    cpu = Map.get(meta, :cpu)
    memory = Map.get(meta, :memory)
    disk = Map.get(meta, :disk)
    synthetic = Map.get(source, :synthetic, false)

    {check_status, severity} =
      cond do
        status == "READY" and numeric_ok?(cpu) and numeric_ok?(memory) and numeric_ok?(disk) and
            not synthetic ->
          {"GREEN", "INFO"}

        status in ["DEGRADED", "WARNING"] or not numeric_ok?(cpu) or not numeric_ok?(memory) or
            not numeric_ok?(disk) ->
          {"ATTENTION", "MEDIUM"}

        status in ["ERROR", "UNAVAILABLE", "NOT_CONFIGURED"] or synthetic ->
          {"BLOCKED", "HIGH"}

        true ->
          {"UNAVAILABLE", "MEDIUM"}
      end

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
          {"disk", disk},
          {"synthetic", synthetic}
        ]),
      action: []
    }
  end

  defp assess_security(overview) do
    source = Map.get(overview, :security, %{})
    status = primary_status(source, "UNAVAILABLE")
    checks = Map.get(source, :checks, %{})
    synthetic = Map.get(source, :synthetic, false)

    {check_status, severity, action} =
      cond do
        status == "PASS" and not synthetic ->
          {"GREEN", "INFO", []}

        status == "DEGRADED" ->
          {"ATTENTION", "HIGH",
           [
             action_for(
               "security-review",
               "SECURITY",
               "Security-Checks reparieren",
               "HIGH",
               build_evidence("security", [{"status", status}]),
               Map.get(@weights, "security-review")
             )
           ]}

        status in ["ERROR", "UNAVAILABLE", "NOT_CONFIGURED"] or synthetic ->
          {"BLOCKED", "CRITICAL",
           [
             action_for(
               "security-review",
               "SECURITY",
               "Security-Status untersuchen (kein verlässliches Signal)",
               "CRITICAL",
               build_evidence("security", [{"status", status}, {"synthetic", synthetic}]),
               Map.get(@weights, "security-review")
             )
           ]}

        true ->
          {"UNAVAILABLE", "MEDIUM", []}
      end

    %{
      domain: "SECURITY",
      status: check_status,
      severity: severity,
      summary: "Security: #{status} (#{map_size(checks)} checks)",
      evidence: build_evidence("security", [{"status", status}, {"synthetic", synthetic}]),
      action: action
    }
  end

  defp assess_services(overview) do
    source = Map.get(overview, :services, %{})
    status = primary_status(source, "UNAVAILABLE")
    records = Map.get(source, :records, [])

    unhealthy =
      Enum.reject(records, fn r -> Map.get(r, :status, "READY") in ["READY", "HEALTHY"] end)

    unhealthy_count = length(unhealthy)
    synthetic = Map.get(source, :synthetic, false)

    {check_status, severity, action} =
      cond do
        status == "READY" and unhealthy_count == 0 and not synthetic ->
          {"GREEN", "INFO", []}

        unhealthy_count > 0 or status in ["DEGRADED", "WARNING"] ->
          {"ATTENTION", "MEDIUM",
           [
             action_for(
               "service-recovery",
               "SERVICES",
               "Beeinträchtigte Dienste prüfen (#{unhealthy_count})",
               "MEDIUM",
               build_evidence("services", [{"status", status}, {"unhealthy", unhealthy_count}]),
               Map.get(@weights, "service-recovery")
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
      evidence:
        build_evidence("services", [
          {"status", status},
          {"unhealthy", unhealthy_count},
          {"synthetic", synthetic}
        ]),
      action: action
    }
  end

  defp assess_backups(overview) do
    source = Map.get(overview, :backups, %{})
    status = primary_status(source, "UNAVAILABLE")
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
             action_for(
               "backup-verify",
               "BACKUPS",
               "Backup-Lage verifizieren (fehlend/veraltet)",
               "HIGH",
               build_evidence("backups", [
                 {"status", status},
                 {"last_success_at", last_success},
                 {"stale", stale}
               ]),
               Map.get(@weights, "backup-verify")
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
      evidence:
        build_evidence("backups", [
          {"status", status},
          {"last_success_at", last_success},
          {"stale", stale},
          {"synthetic", synthetic}
        ]),
      action: action
    }
  end

  defp assess_approvals(overview) do
    source = Map.get(overview, :approvals, %{})
    status = primary_status(source, "UNAVAILABLE")
    records = Map.get(source, :records, [])

    pending =
      Enum.filter(records, fn r -> Map.get(r, :status, "") in ["PENDING", "REQUESTED"] end)

    pending_count = length(pending)

    {check_status, severity, action} =
      cond do
        status == "READY" and pending_count == 0 ->
          {"GREEN", "INFO", []}

        pending_count > 0 ->
          {"ATTENTION", "MEDIUM",
           [
             action_for(
               "approval-clear",
               "APPROVALS",
               "#{pending_count} offene Freigaben bearbeiten",
               "MEDIUM",
               build_evidence("approvals", [{"pending", pending_count}]),
               Map.get(@weights, "approval-clear")
             )
           ]}

        true ->
          {"UNAVAILABLE", "LOW", []}
      end

    %{
      domain: "APPROVALS",
      status: check_status,
      severity: severity,
      summary: "Approvals: #{status} (#{pending_count} pending)",
      evidence: build_evidence("approvals", [{"status", status}, {"pending", pending_count}]),
      action: action
    }
  end

  defp assess_failed_runs(overview) do
    source = Map.get(overview, :runs, %{})
    status = primary_status(source, "UNAVAILABLE")
    records = Map.get(source, :records, [])

    failed =
      Enum.filter(records, fn r -> Map.get(r, :status, "") in ["FAILED", "ERROR", "ABORTED"] end)

    failed_count = length(failed)

    {check_status, severity, action} =
      cond do
        status == "READY" and failed_count == 0 ->
          {"GREEN", "INFO", []}

        failed_count > 0 ->
          {"ATTENTION", "HIGH",
           [
             action_for(
               "failed-run-recover",
               "FAILED_RUNS",
               "#{failed_count} fehlgeschlagene Workflow-Runs untersuchen",
               "HIGH",
               build_evidence("failed_runs", [{"failed", failed_count}]),
               Map.get(@weights, "failed-run-recover")
             )
           ]}

        true ->
          {"UNAVAILABLE", "MEDIUM", []}
      end

    %{
      domain: "FAILED_RUNS",
      status: check_status,
      severity: severity,
      summary: "Runs: #{status} (#{failed_count} failed)",
      evidence: build_evidence("failed_runs", [{"status", status}, {"failed", failed_count}]),
      action: action
    }
  end

  defp assess_career(overview) do
    source = Map.get(overview, :career, %{})
    status = primary_status(source, "UNAVAILABLE")
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
      evidence:
        build_evidence("career", [
          {"status", status},
          {"ihk_workflow", ihk_status},
          {"synthetic", synthetic}
        ]),
      action: []
    }
  end

  defp assess_ihk(ihk_domain) do
    status = primary_status(ihk_domain, "UNAVAILABLE")
    records = Map.get(ihk_domain, :records, [])
    record_count = length(records)
    synthetic = Map.get(ihk_domain, :synthetic, false)

    {check_status, severity, action} =
      cond do
        status == "READY" and record_count > 0 and not synthetic ->
          {"GREEN", "INFO", []}

        status == "READY" and record_count == 0 ->
          {"ATTENTION", "MEDIUM",
           [
             action_for(
               "ihk-evidence",
               "IHK",
               "Keine IHK/BA Evidenz im Projekt-Domain vorhanden",
               "MEDIUM",
               build_evidence("ihk", [{"status", status}, {"records", 0}]),
               Map.get(@weights, "ihk-evidence")
             )
           ]}

        status in ["NOT_CONFIGURED", "UNAVAILABLE", "ERROR"] ->
          {"ATTENTION", "MEDIUM",
           [
             action_for(
               "ihk-evidence",
               "IHK",
               "IHK/BA Evidenz-Domain nicht verfügbar",
               "MEDIUM",
               build_evidence("ihk", [{"status", status}]),
               Map.get(@weights, "ihk-evidence")
             )
           ]}

        true ->
          {"UNAVAILABLE", "MEDIUM", []}
      end

    %{
      domain: "IHK",
      status: check_status,
      severity: severity,
      summary: "IHK/BA: #{status} (#{record_count} records)",
      evidence:
        build_evidence("ihk", [
          {"status", status},
          {"records", record_count},
          {"synthetic", synthetic}
        ]),
      action: action
    }
  end

  defp assess_evidence(overview) do
    source = Map.get(overview, :evidence, %{})
    status = primary_status(source, "UNAVAILABLE")
    records = Map.get(source, :records, [])
    synthetic = Map.get(source, :synthetic, false)
    real_data = Map.get(source, :real_data, false)
    any_synthetic = synthetic or Enum.any?(records, fn r -> Map.get(r, :synthetic, false) end)

    {check_status, severity} =
      cond do
        status == "READY" and length(records) > 0 and real_data and not any_synthetic ->
          {"GREEN", "INFO"}

        status in ["ERROR", "UNAVAILABLE", "NOT_CONFIGURED"] ->
          {"BLOCKED", "MEDIUM"}

        any_synthetic ->
          {"ATTENTION", "MEDIUM"}

        true ->
          {"ATTENTION", "LOW"}
      end

    %{
      domain: "EVIDENCE",
      status: check_status,
      severity: severity,
      summary: "Evidence: #{status} (#{length(records)} records, synthetic=#{any_synthetic})",
      evidence:
        build_evidence("evidence", [
          {"status", status},
          {"records", length(records)},
          {"synthetic", any_synthetic}
        ]),
      action: []
    }
  end

  # --- ranking (deterministic, no LLM) ---

  defp action_for(id, domain, title, severity, evidence, weights) when is_map(weights) do
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

  defp primary_status(nil, default), do: default

  defp primary_status(source, default) when is_map(source),
    do: Map.get(source, :status, Map.get(source, :overall, default))

  defp primary_status(_, default), do: default

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
      {"APPROVALS", Map.get(overview, :approvals, %{})},
      {"FAILED_RUNS", Map.get(overview, :runs, %{})},
      {"CAREER", Map.get(overview, :career, %{})},
      {"EVIDENCE", Map.get(overview, :evidence, %{})},
      {"IHK", ihk_domain}
    ]

    Enum.map(domains, fn {name, source} ->
      %{
        domain: name,
        status: primary_status(source, "UNAVAILABLE"),
        available:
          primary_status(source, "UNAVAILABLE") not in ["UNAVAILABLE", "NOT_CONFIGURED", "ERROR"],
        synthetic: Map.get(source, :synthetic, false)
      }
    end)
  end

  defp summary_text(_overview, "GREEN", _checks),
    do: "Alle geprüften Bereiche sind im grünen Bereich."

  defp summary_text(_overview, status, checks) do
    attention =
      checks
      |> Enum.reject(&(Map.get(&1, :status) == "GREEN"))
      |> Enum.map(&Map.get(&1, :domain))
      |> Enum.join(", ")

    "Status #{status}. Aufmerksamkeit erforderlich in: #{attention}."
  end
end
