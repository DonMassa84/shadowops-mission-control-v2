defmodule ShadowOpsWeb.HighValueWorkflows do
  @moduledoc """
  Fail-closed projections for five high-value ShadowOps workflows.

  Runtime IO is collected once through RuntimeOverview and then projected purely.
  Release readiness is based on an exact-HEAD certificate; actual certification
  remains behind the existing governed OneClick/ExecutionService path.
  """

  alias ShadowOpsWeb.{ProjectDomains, RuntimeOverview}

  @positive ~w(READY ONLINE CONNECTED AVAILABLE HEALTHY VALID PASS GREEN)
  @not_applicable ~w(NOT_APPLICABLE OPTIONAL_UNAVAILABLE)
  @severity_rank %{"INFO" => 0, "LOW" => 1, "MEDIUM" => 2, "HIGH" => 3, "CRITICAL" => 4}

  @workflow_ids %{
    daily_control: "so:wf:v1:daily-control",
    system_doctor: "so:wf:v1:system-doctor",
    release_acceptance: "so:wf:v1:release-acceptance",
    ihk_evidence_gate: "so:wf:v1:ihk-evidence-gate",
    career_control: "so:wf:v1:career-control"
  }

  def all, do: collect_sources() |> from_sources()

  def snapshot(kind) do
    case Map.fetch(all(), normalize_kind(kind)) do
      {:ok, result} -> {:ok, result}
      :error -> {:error, :unknown_high_value_workflow}
    end
  end

  @doc false
  def from_sources(sources) when is_map(sources) do
    system = system_doctor(sources)
    release = release_acceptance(sources)
    ihk = ihk_evidence_gate(sources)
    career = career_control(sources)

    daily =
      daily_control(sources, %{
        system_doctor: system,
        release_acceptance: release,
        ihk_evidence_gate: ihk,
        career_control: career
      })

    %{
      daily_control: daily,
      system_doctor: system,
      release_acceptance: release,
      ihk_evidence_gate: ihk,
      career_control: career
    }
  end

  defp collect_sources do
    %{
      overview: RuntimeOverview.snapshot(),
      ihk_domain: safe_source(fn -> ProjectDomains.snapshot(:ihk) end, "ihk"),
      career_domain: safe_source(fn -> ProjectDomains.snapshot(:career) end, "career"),
      release: release_source()
    }
  end

  defp daily_control(sources, specialized) do
    overview = value(sources, :overview, %{})

    approval_count =
      overview
      |> value(:approvals, %{})
      |> value(:records, [])
      |> List.wrap()
      |> Enum.count(&(value(&1, :status, "") == "PENDING"))

    failed_runs =
      overview
      |> value(:runs, %{})
      |> value(:records, [])
      |> List.wrap()
      |> Enum.count(&(value(&1, :status, "") in ["FAILED", "BLOCKED", "ERROR"]))

    checks = [
      workflow_check("system", "System Doctor", specialized.system_doctor),
      workflow_check("release", "Release Acceptance", specialized.release_acceptance),
      workflow_check("ihk", "IHK Evidence", specialized.ihk_evidence_gate),
      workflow_check("career", "Career Control", specialized.career_control),
      count_check("approvals", "Pending approvals", approval_count, "approval store", "HIGH"),
      count_check("failed_runs", "Failed or blocked runs", failed_runs, "run store", "HIGH")
    ]

    actions =
      specialized
      |> Map.values()
      |> Enum.flat_map(&value(&1, :next_actions, []))
      |> add_count_action(
        approval_count,
        action(
          "daily.approvals",
          "governance",
          "Review pending approvals",
          "Governed actions are waiting for an operator decision.",
          "/approvals",
          5,
          5,
          5,
          5,
          5,
          1
        )
      )
      |> add_count_action(
        failed_runs,
        action(
          "daily.failed-runs",
          "operations",
          "Review failed workflow runs",
          "One or more workflow runs are FAILED/BLOCKED/ERROR.",
          "/runs",
          5,
          5,
          5,
          4,
          5,
          2
        )
      )
      |> rank_actions()

    result(
      @workflow_ids.daily_control,
      checks,
      actions,
      "Daily operational control across specialized ShadowOps workflows."
    )
    |> Map.put(:top_actions, actions)
  end

  defp system_doctor(sources) do
    overview = value(sources, :overview, %{})
    system = value(overview, :system, %{})
    services = value(overview, :services, %{})
    security = value(overview, :security, %{})
    backups = value(overview, :backups, %{})
    audit = value(overview, :audit, %{})
    readiness = value(overview, :readiness, %{})

    service_rows =
      services
      |> value(:services, value(services, :records, []))
      |> List.wrap()

    degraded_services =
      Enum.reject(service_rows, fn service ->
        value(service, :status, "UNKNOWN") in ["READY", "OPTIONAL_UNAVAILABLE"]
      end)

    checks = [
      source_state_check(
        "runtime_readiness",
        "Runtime readiness",
        value(readiness, :state, "UNAVAILABLE"),
        "runtime readiness",
        "HIGH"
      ),
      source_state_check(
        "system_source",
        "System source",
        source_status(system),
        value(system, :source, "system runtime"),
        "HIGH"
      ),
      disk_check(value(system, :disk, nil)),
      memory_check(value(system, :ram, nil)),
      temperature_check(value(system, :temperatures_c, nil)),
      collection_check(
        "services",
        "Runtime services",
        service_rows,
        degraded_services,
        value(services, :source, "services runtime")
      ),
      source_state_check(
        "security",
        "Security",
        first_state(security),
        value(security, :source, "security projection"),
        "CRITICAL"
      ),
      source_state_check(
        "backups",
        "Backup verification",
        source_status(backups),
        value(backups, :source, "backup source"),
        "HIGH",
        require_real: true,
        source_record: backups
      ),
      audit_check(audit)
    ]

    actions =
      []
      |> maybe_action(
        Enum.any?(checks, &(&1.id == "security" and &1.status != "GREEN")),
        action(
          "system.security",
          "security",
          "Review security findings",
          "Security is not positively verified.",
          "/security",
          5,
          5,
          5,
          5,
          5,
          2
        )
      )
      |> maybe_action(
        Enum.any?(checks, &(&1.id == "disk" and &1.status != "GREEN")),
        action(
          "system.disk",
          "infrastructure",
          "Free disk capacity",
          "Root filesystem usage crossed the attention threshold.",
          "/infrastructure",
          5,
          4,
          5,
          4,
          5,
          2
        )
      )
      |> maybe_action(
        degraded_services != [],
        action(
          "system.services",
          "operations",
          "Review degraded services",
          "#{length(degraded_services)} service(s) are not READY.",
          "/services",
          4,
          4,
          5,
          4,
          5,
          2
        )
      )
      |> maybe_action(
        Enum.any?(checks, &(&1.id == "backups" and &1.status != "GREEN")),
        action(
          "system.backups",
          "operations",
          "Verify backups",
          "Backup evidence is unavailable or not verified.",
          "/backups",
          5,
          4,
          5,
          4,
          5,
          2
        )
      )
      |> rank_actions()

    result(
      @workflow_ids.system_doctor,
      checks,
      actions,
      "Read-only diagnosis of system, services, security, audit and backup evidence."
    )
  end

  defp release_acceptance(sources) do
    release = value(sources, :release, %{})

    required =
      ~w(FORMAT COMPILE TESTS CREDO DIALYZER SOBELOW REGISTRY WORKFLOW_IDS HEX_AUDIT PRODUCTION_HANDOFF MCP_CONTRACT LOCAL_CODER_CONTRACT)

    cert = value(release, :certificate, %{})
    exact_head = value(release, :certificate_head, nil) == value(release, :head, nil)

    gate_checks =
      Enum.map(required, fn gate ->
        state = Map.get(cert, gate)
        id = "release." <> String.downcase(gate)

        cond do
          not value(release, :certificate_present, false) ->
            check(
              id,
              gate,
              "UNAVAILABLE",
              "HIGH",
              value(release, :certificate_path, "certified release")
            )

          not exact_head ->
            check(id, gate, "ATTENTION", "HIGH", "certificate HEAD mismatch")

          state == "PASS" ->
            check(id, gate, "GREEN", "INFO", "exact-HEAD release certificate")

          true ->
            check(id, gate, "ATTENTION", "HIGH", "exact-HEAD release certificate")
        end
      end)

    branch_check =
      if value(release, :branch, nil) == value(release, :target_branch, "local/all-developments") do
        check("release.branch", "Canonical release branch", "GREEN", "INFO", "git")
      else
        check(
          "release.branch",
          "Canonical release branch",
          "ATTENTION",
          "MEDIUM",
          "git",
          ["current=#{value(release, :branch, "UNKNOWN")}"]
        )
      end

    checks = [branch_check | gate_checks]
    ready = exact_head and Enum.all?(checks, &(&1.status == "GREEN"))

    actions =
      []
      |> maybe_action(
        not ready,
        action(
          "release.certify",
          "release",
          "Run governed release acceptance",
          "No complete exact-HEAD certification exists for the current source.",
          "/control",
          5,
          5,
          4,
          5,
          5,
          4
        )
      )
      |> rank_actions()

    result(
      @workflow_ids.release_acceptance,
      checks,
      actions,
      "Exact-HEAD release certificate and required quality/security gates."
    )
    |> Map.put(:release_ready, ready)
    |> Map.put(:head, value(release, :head, nil))
    |> Map.put(:branch, value(release, :branch, nil))
    |> Map.put(:certificate_path, value(release, :certificate_path, nil))
  end

  defp ihk_evidence_gate(sources) do
    overview = value(sources, :overview, %{})
    evidence = value(overview, :evidence, %{})
    domain = value(sources, :ihk_domain, %{})
    artifacts = value(evidence, :artifacts, []) |> List.wrap()

    requirements = [
      {"project_application", ~w(antrag application projektantrag)},
      {"hours", ~w(stunden hours zeitaufwand)},
      {"costs", ~w(kosten cost wirtschaftlichkeit)},
      {"tests", ~w(test tests testcase)},
      {"acceptance", ~w(abnahme acceptance freigabe)},
      {"implementation", ~w(implementation umsetzung implementierung)},
      {"ci", ~w(ci github workflow actions)},
      {"sources", ~w(quelle quellen source sources)}
    ]

    evidence_states =
      Enum.map(requirements, fn {id, patterns} ->
        evidence_requirement(id, patterns, artifacts)
      end)

    verified = Enum.count(evidence_states, &(&1.state == "VERIFIED"))
    weak = Enum.count(evidence_states, &(&1.state == "WEAK"))
    missing = Enum.count(evidence_states, &(&1.state == "MISSING"))
    total = length(evidence_states)
    score = if total == 0, do: 0, else: round((verified + weak * 0.5) / total * 100)

    domain_check =
      source_state_check(
        "ihk.domain",
        "IHK project manifest",
        source_status(domain),
        value(domain, :source, "IHK domain manifest"),
        "HIGH",
        require_real: true,
        source_record: domain
      )

    evidence_check =
      cond do
        missing > 0 ->
          check(
            "ihk.evidence",
            "IHK evidence completeness",
            "ATTENTION",
            "HIGH",
            "project evidence directory",
            ["verified=#{verified}", "weak=#{weak}", "missing=#{missing}"]
          )

        weak > 0 ->
          check(
            "ihk.evidence",
            "IHK evidence completeness",
            "ATTENTION",
            "MEDIUM",
            "project evidence directory",
            ["verified=#{verified}", "weak=#{weak}", "missing=0"]
          )

        total > 0 ->
          check(
            "ihk.evidence",
            "IHK evidence completeness",
            "GREEN",
            "INFO",
            "project evidence directory",
            ["verified=#{verified}", "weak=0", "missing=0"]
          )

        true ->
          check(
            "ihk.evidence",
            "IHK evidence completeness",
            "UNAVAILABLE",
            "HIGH",
            "project evidence directory"
          )
      end

    checks = [domain_check, evidence_check]

    actions =
      evidence_states
      |> Enum.filter(&(&1.state in ["MISSING", "WEAK"]))
      |> Enum.map(fn item ->
        action(
          "ihk." <> item.id,
          "ihk",
          if(item.state == "MISSING",
            do: "Close missing IHK evidence",
            else: "Strengthen weak IHK evidence"
          ),
          "#{item.id}: #{item.state}",
          "/projects/ihk",
          if(item.state == "MISSING", do: 5, else: 4),
          4,
          5,
          5,
          if(item.state == "MISSING", do: 5, else: 3),
          2
        )
      end)
      |> rank_actions()

    result(
      @workflow_ids.ihk_evidence_gate,
      checks,
      actions,
      "Deterministic IHK evidence completeness; file presence alone is never VERIFIED."
    )
    |> Map.put(:evidence_score, score)
    |> Map.put(:verified_count, verified)
    |> Map.put(:weak_count, weak)
    |> Map.put(:missing_count, missing)
    |> Map.put(:requirements, evidence_states)
    |> Map.put(:blockers, Enum.filter(evidence_states, &(&1.state == "MISSING")))
  end

  defp career_control(sources) do
    overview = value(sources, :overview, %{})
    career = value(overview, :career, %{})
    domain = value(sources, :career_domain, %{})
    applications = value(career, :applications, value(career, :records, nil))
    pipeline_available = is_list(applications)

    runtime_check =
      source_state_check(
        "career.runtime",
        "Career runtime",
        source_status(career),
        value(career, :source, "career runtime"),
        "HIGH",
        require_real: true,
        source_record: career
      )

    domain_check =
      source_state_check(
        "career.domain",
        "Career project manifest",
        source_status(domain),
        value(domain, :source, "career domain manifest"),
        "MEDIUM",
        require_real: true,
        source_record: domain
      )

    pipeline_check =
      if pipeline_available do
        check(
          "career.pipeline",
          "Application pipeline",
          "GREEN",
          "INFO",
          "career runtime",
          ["records=#{length(applications)}"]
        )
      else
        check(
          "career.pipeline",
          "Application pipeline",
          "UNAVAILABLE",
          "HIGH",
          value(career, :source, "career runtime"),
          ["No structured application list is exposed; no follow-up state is fabricated"]
        )
      end

    {pipeline_checks, pipeline_actions} =
      if pipeline_available, do: classify_applications(applications), else: {[], []}

    checks = [runtime_check, domain_check, pipeline_check | pipeline_checks]

    actions =
      pipeline_actions
      |> maybe_action(
        runtime_check.status != "GREEN",
        action(
          "career.runtime",
          "career",
          "Restore career source",
          "Career runtime evidence is not READY/real.",
          "/career",
          5,
          5,
          5,
          5,
          5,
          2
        )
      )
      |> maybe_action(
        pipeline_check.status != "GREEN",
        action(
          "career.pipeline",
          "career",
          "Connect structured career pipeline",
          "Current source has no application-level records; no fake Gmail/application state is created.",
          "/career",
          4,
          4,
          4,
          5,
          5,
          3
        )
      )
      |> rank_actions()

    result(
      @workflow_ids.career_control,
      checks,
      actions,
      "Read-only career control; missing Gmail/application evidence remains explicit."
    )
    |> Map.put(:pipeline_available, pipeline_available)
    |> Map.put(:application_count, if(pipeline_available, do: length(applications), else: nil))
  end

  defp classify_applications(applications) do
    Enum.reduce(applications, {[], []}, fn application, {checks, actions} ->
      id = value(application, :id, value(application, :company, "application"))
      state = value(application, :status, "UNKNOWN")
      age = days_since(value(application, :updated_at, value(application, :last_contact_at, nil)))

      {status, severity, action_item} =
        cond do
          state == "BOUNCE" ->
            {"ATTENTION", "HIGH",
             action(
               "career.bounce." <> safe_id(id),
               "career",
               "Resolve bounced application",
               "#{id} is marked BOUNCE.",
               "/career",
               5,
               5,
               5,
               5,
               5,
               2
             )}

          state == "INTERVIEW" ->
            {"ATTENTION", "HIGH",
             action(
               "career.interview." <> safe_id(id),
               "career",
               "Prepare interview",
               "#{id} is in INTERVIEW state.",
               "/career",
               5,
               5,
               5,
               5,
               5,
               2
             )}

          state == "WAITING" and is_integer(age) and age >= 7 ->
            {"ATTENTION", "MEDIUM",
             action(
               "career.followup." <> safe_id(id),
               "career",
               "Prepare follow-up",
               "#{id} has been WAITING for #{age} day(s).",
               "/career",
               4,
               4,
               5,
               5,
               4,
               2
             )}

          state in ~w(NEW_LEAD PREPARING SENT WAITING REJECTED CONFIRMED CLOSED FOLLOW_UP) ->
            {"GREEN", "INFO", nil}

          true ->
            {"UNAVAILABLE", "MEDIUM", nil}
        end

      row =
        check(
          "career.application." <> safe_id(id),
          to_string(id),
          status,
          severity,
          "career application state",
          ["state=#{state}", "age_days=#{inspect(age)}"]
        )

      {checks ++ [row], if(action_item, do: actions ++ [action_item], else: actions)}
    end)
  end

  defp evidence_requirement(id, patterns, artifacts) do
    match =
      Enum.find(artifacts, fn artifact ->
        name = artifact |> value(:artifact, "") |> String.downcase()
        Enum.any?(patterns, &String.contains?(name, &1))
      end)

    case match do
      nil ->
        %{id: id, state: "MISSING", artifact: nil, evidence: []}

      artifact ->
        verification = value(artifact, :verification_status, "AVAILABLE")
        state = if verification in ["VERIFIED", "PASS", "CONFIRMED"], do: "VERIFIED", else: "WEAK"

        %{
          id: id,
          state: state,
          artifact: value(artifact, :artifact, nil),
          evidence: [value(artifact, :artifact, "artifact")]
        }
    end
  end

  defp release_source do
    root = repo_root()
    head = git_value(root, ["rev-parse", "HEAD"])
    branch = git_value(root, ["branch", "--show-current"])
    target = System.get_env("SHADOWOPS_CERT_BRANCH") || "local/all-developments"

    state_root =
      System.get_env("SHADOWOPS_STATE_ROOT") ||
        Path.join(System.user_home!(), ".local/state/shadowops")

    cert_path =
      if is_binary(head),
        do: Path.join([state_root, "certified-releases", head <> ".env"]),
        else: nil

    certificate = if is_binary(cert_path), do: parse_env_file(cert_path), else: %{}

    %{
      repo_root: root,
      head: head,
      branch: branch,
      target_branch: target,
      certificate_present: is_binary(cert_path) and File.regular?(cert_path),
      certificate_path: cert_path,
      certificate_head: Map.get(certificate, "HEAD"),
      certificate: certificate
    }
  rescue
    _ ->
      %{
        head: nil,
        branch: nil,
        target_branch: "local/all-developments",
        certificate_present: false,
        certificate_path: nil,
        certificate_head: nil,
        certificate: %{}
      }
  end

  defp repo_root do
    Application.fetch_env!(:workflow_engine, :registry_path)
    |> Path.expand()
    |> Path.dirname()
    |> Path.dirname()
  end

  defp git_value(root, args) when is_binary(root) do
    case System.cmd("git", args, cd: root, stderr_to_stdout: true) do
      {value, 0} -> String.trim(value)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp parse_env_file(path) do
    case File.read(path) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.reject(&String.starts_with?(&1, "#"))
        |> Enum.flat_map(fn line ->
          case String.split(line, "=", parts: 2) do
            [key, val] -> [{key, val}]
            _ -> []
          end
        end)
        |> Map.new()

      _ ->
        %{}
    end
  end

  defp safe_source(fun, id) do
    fun.()
  rescue
    error ->
      %{
        id: id,
        status: "UNAVAILABLE",
        health: "UNKNOWN",
        real_data: false,
        synthetic: false,
        reachable: false,
        source: "bounded local source",
        error_message: Exception.message(error)
      }
  end

  defp source_state_check(id, title, state, source, severity, opts \\ []) do
    source_record = Keyword.get(opts, :source_record, %{})
    require_real = Keyword.get(opts, :require_real, false)
    real_ok = not require_real or value(source_record, :real_data, false) == true
    synthetic_ok = value(source_record, :synthetic, false) != true

    status =
      cond do
        state in @not_applicable ->
          "NOT_APPLICABLE"

        state in @positive and real_ok and synthetic_ok ->
          "GREEN"

        state in ["BLOCKED", "ERROR", "FAIL", "INVALID"] ->
          "BLOCKED"

        state in ["UNAVAILABLE", "NOT_CONFIGURED", "NOT_CONNECTED", "UNKNOWN", nil, ""] ->
          "UNAVAILABLE"

        true ->
          "ATTENTION"
      end

    check(id, title, status, severity_for(status, severity), source, [
      "source_state=#{inspect(state)}"
    ])
  end

  defp audit_check(audit) do
    cond do
      value(audit, :valid, false) == true or first_state(audit) in @positive ->
        check("audit", "Audit integrity", "GREEN", "INFO", value(audit, :source, "audit"))

      first_state(audit) in ["INVALID", "ERROR", "FAIL"] ->
        check("audit", "Audit integrity", "BLOCKED", "CRITICAL", value(audit, :source, "audit"))

      true ->
        check("audit", "Audit integrity", "UNAVAILABLE", "HIGH", value(audit, :source, "audit"))
    end
  end

  defp disk_check(nil),
    do: check("disk", "Root filesystem", "UNAVAILABLE", "HIGH", "system source")

  defp disk_check(disk) do
    used = parse_percent(value(disk, :used_percent, nil))

    cond do
      is_nil(used) ->
        check("disk", "Root filesystem", "UNAVAILABLE", "HIGH", "df")

      used >= 95 ->
        check("disk", "Root filesystem", "BLOCKED", "CRITICAL", "df", ["used_percent=#{used}"])

      used >= 85 ->
        check("disk", "Root filesystem", "ATTENTION", "HIGH", "df", ["used_percent=#{used}"])

      true ->
        check("disk", "Root filesystem", "GREEN", "INFO", "df", ["used_percent=#{used}"])
    end
  end

  defp memory_check(nil),
    do: check("memory", "Available memory", "UNAVAILABLE", "MEDIUM", "/proc/meminfo")

  defp memory_check(ram) do
    total = value(ram, :total_bytes, nil)
    available = value(ram, :available_bytes, nil)

    ratio =
      if is_number(total) and total > 0 and is_number(available),
        do: available / total,
        else: nil

    cond do
      is_nil(ratio) ->
        check("memory", "Available memory", "UNAVAILABLE", "MEDIUM", "/proc/meminfo")

      ratio <= 0.05 ->
        check("memory", "Available memory", "BLOCKED", "CRITICAL", "/proc/meminfo")

      ratio <= 0.10 ->
        check("memory", "Available memory", "ATTENTION", "HIGH", "/proc/meminfo")

      true ->
        check("memory", "Available memory", "GREEN", "INFO", "/proc/meminfo")
    end
  end

  defp temperature_check(nil),
    do: check("temperature", "Temperatures", "NOT_APPLICABLE", "INFO", "/sys/class/thermal")

  defp temperature_check(values) do
    numbers =
      values
      |> List.wrap()
      |> Enum.flat_map(fn
        value when is_number(value) -> [value]
        %{temperature_c: value} when is_number(value) -> [value]
        %{"temperature_c" => value} when is_number(value) -> [value]
        _ -> []
      end)

    case numbers do
      [] ->
        check("temperature", "Temperatures", "NOT_APPLICABLE", "INFO", "/sys/class/thermal")

      _ ->
        max_temp = Enum.max(numbers)

        cond do
          max_temp >= 90 ->
            check("temperature", "Temperatures", "BLOCKED", "CRITICAL", "/sys/class/thermal", [
              "max_c=#{max_temp}"
            ])

          max_temp >= 80 ->
            check("temperature", "Temperatures", "ATTENTION", "HIGH", "/sys/class/thermal", [
              "max_c=#{max_temp}"
            ])

          true ->
            check("temperature", "Temperatures", "GREEN", "INFO", "/sys/class/thermal", [
              "max_c=#{max_temp}"
            ])
        end
    end
  end

  defp collection_check(id, title, rows, bad_rows, source) do
    cond do
      rows == [] ->
        check(id, title, "UNAVAILABLE", "HIGH", source)

      bad_rows == [] ->
        check(id, title, "GREEN", "INFO", source, ["records=#{length(rows)}"])

      true ->
        check(id, title, "ATTENTION", "HIGH", source, [
          "degraded=#{length(bad_rows)}",
          "records=#{length(rows)}"
        ])
    end
  end

  defp workflow_check(id, title, workflow) do
    check(
      id,
      title,
      value(workflow, :status, "UNAVAILABLE"),
      value(workflow, :severity, "HIGH"),
      value(workflow, :workflow_id, "workflow projection")
    )
  end

  defp count_check(id, title, count, source, severity) do
    if count > 0,
      do: check(id, title, "ATTENTION", severity, source, ["count=#{count}"]),
      else: check(id, title, "GREEN", "INFO", source, ["count=0"])
  end

  defp check(id, title, status, severity, source, evidence \\ []) do
    %{
      id: id,
      title: title,
      status: status,
      severity: severity,
      source: source,
      evidence: List.wrap(evidence),
      attention_required: status not in ["GREEN", "NOT_APPLICABLE"]
    }
  end

  defp result(workflow_id, checks, actions, summary) do
    effective = Enum.reject(checks, &(&1.status == "NOT_APPLICABLE"))

    status =
      cond do
        Enum.any?(effective, &(&1.status == "BLOCKED")) -> "BLOCKED"
        Enum.any?(effective, &(&1.status == "ATTENTION")) -> "ATTENTION"
        Enum.any?(effective, &(&1.status == "UNAVAILABLE")) -> "UNAVAILABLE"
        effective != [] and Enum.all?(effective, &(&1.status == "GREEN")) -> "GREEN"
        true -> "UNAVAILABLE"
      end

    severity =
      effective
      |> Enum.filter(&(&1.status != "GREEN"))
      |> Enum.map(& &1.severity)
      |> highest_severity()

    %{
      workflow_id: workflow_id,
      status: status,
      severity: severity,
      summary: summary,
      attention_required: status != "GREEN",
      checks: checks,
      next_actions: actions,
      evidence: Enum.flat_map(checks, & &1.evidence),
      source_status: Enum.map(checks, &Map.take(&1, [:id, :status, :source])),
      synthetic: false,
      generated_at: now()
    }
  end

  defp action(
         id,
         domain,
         title,
         reason,
         href,
         impact,
         urgency,
         success,
         strategic,
         evidence,
         effort
       ) do
    %{
      id: id,
      domain: domain,
      title: title,
      reason: reason,
      href: href,
      impact: impact,
      urgency: urgency,
      success_probability: success,
      strategic_alignment: strategic,
      evidence_confidence: evidence,
      effort: effort
    }
  end

  defp rank_actions(actions) do
    actions
    |> Enum.uniq_by(& &1.id)
    |> Enum.map(fn item ->
      score =
        item.impact * 3 +
          item.urgency * 3 +
          item.success_probability * 2 +
          item.strategic_alignment * 2 +
          item.evidence_confidence * 2 -
          item.effort

      Map.put(item, :score, score)
    end)
    |> Enum.sort_by(fn item -> {-item.score, item.id} end)
    |> Enum.take(3)
    |> Enum.with_index(1)
    |> Enum.map(fn {item, rank} -> Map.put(item, :rank, rank) end)
  end

  defp maybe_action(actions, true, item), do: [item | actions]
  defp maybe_action(actions, false, _item), do: actions
  defp add_count_action(actions, count, item) when count > 0, do: [item | actions]
  defp add_count_action(actions, _count, _item), do: actions

  defp normalize_kind(kind) when is_atom(kind), do: kind

  defp normalize_kind(kind) when is_binary(kind) do
    case String.replace(kind, "_", "-") do
      "daily-control" -> :daily_control
      "system-doctor" -> :system_doctor
      "release-acceptance" -> :release_acceptance
      "ihk-evidence-gate" -> :ihk_evidence_gate
      "career-control" -> :career_control
      _ -> :unknown
    end
  end

  defp first_state(map) do
    value(map, :overall, nil) ||
      value(map, :status, nil) ||
      value(map, :state, nil) ||
      value(map, :health, "UNAVAILABLE")
  end

  defp source_status(map), do: first_state(map)

  defp severity_for("GREEN", _default), do: "INFO"
  defp severity_for("NOT_APPLICABLE", _default), do: "INFO"
  defp severity_for(_status, default), do: default

  defp highest_severity([]), do: "INFO"
  defp highest_severity(values), do: Enum.max_by(values, &Map.get(@severity_rank, &1, 0))

  defp parse_percent(value) when is_integer(value), do: value
  defp parse_percent(value) when is_float(value), do: round(value)

  defp parse_percent(value) when is_binary(value) do
    case Integer.parse(String.trim_trailing(value, "%")) do
      {number, _} -> number
      _ -> nil
    end
  end

  defp parse_percent(_), do: nil

  defp days_since(nil), do: nil

  defp days_since(value) when is_binary(value) do
    with {:ok, dt, _offset} <- DateTime.from_iso8601(value) do
      div(DateTime.diff(DateTime.utc_now(), dt, :second), 86_400)
    else
      _ -> nil
    end
  end

  defp days_since(_), do: nil

  defp safe_id(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/u, "-")
    |> String.trim("-")
  end

  defp value(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, to_string(key), default))

  defp value(_map, _key, default), do: default

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
