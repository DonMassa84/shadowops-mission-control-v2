defmodule ShadowOpsCore.LocalIntegrationCandidates do
  @moduledoc """
  Read-only discovery for local workflow/service/integration candidates.

  ShadowOps keeps the existing fixed candidate inventory and supplements it with
  a bounded scan of known local automation folders. Discovery never executes a
  script, starts a service, follows symlinked files, reads secret contents, or
  promotes filesystem presence to READY. Presence proves only DISCOVERED.
  """

  @max_auto_records 250

  @scan_patterns [
    "DokumentenSystem/07_AUTOMATION/**/*.service",
    "DokumentenSystem/07_AUTOMATION/**/*.timer",
    "DokumentenSystem/07_AUTOMATION/**/*.sh",
    "DokumentenSystem/07_AUTOMATION/**/*.py",
    "DokumentenSystem/07_AUTOMATION/**/*.exs",
    "DokumentenSystem/09_BOT_GATEWAY/**/*.service",
    "DokumentenSystem/09_BOT_GATEWAY/**/*.timer",
    "DokumentenSystem/09_BOT_GATEWAY/**/*.sh",
    "DokumentenSystem/09_BOT_GATEWAY/**/*.py",
    "DokumentenSystem/.github/workflows/*.yml",
    "DokumentenSystem/.github/workflows/*.yaml"
  ]

  @candidates [
    %{
      id: "bot_gateway",
      name: "Bot Gateway",
      kind: "SYSTEMD_SERVICE",
      domain: "system",
      priority: "HIGH",
      relative_path: "DokumentenSystem/09_BOT_GATEWAY/scripts/bot-gateway.service"
    },
    %{
      id: "system_healer",
      name: "System Healer",
      kind: "WORKFLOW_CANDIDATE",
      domain: "system",
      priority: "HIGH",
      relative_path: "DokumentenSystem/07_AUTOMATION/system_healer.sh"
    },
    %{
      id: "documentation_factory",
      name: "Documentation Factory",
      kind: "SERVICE_FAMILY",
      domain: "documents",
      priority: "MEDIUM",
      relative_glob: "DokumentenSystem/07_AUTOMATION/documentation_factory/systemd/*.service"
    },
    %{
      id: "voice_agent",
      name: "Voice Agent",
      kind: "AGENT_SERVICE_FAMILY",
      domain: "ai",
      priority: "MEDIUM",
      relative_glob: "DokumentenSystem/07_AUTOMATION/voice_agent/systemd/*.service"
    },
    %{
      id: "research_agent",
      name: "Research Agent",
      kind: "AGENT_WORKFLOW_FAMILY",
      domain: "documents",
      priority: "MEDIUM",
      relative_glob: "DokumentenSystem/07_AUTOMATION/research_learning_agent/systemd/*.service"
    },
    %{
      id: "moving_material",
      name: "Moving Material Workflow",
      kind: "WORKFLOW_FAMILY",
      domain: "documents",
      priority: "LOW",
      relative_glob: "DokumentenSystem/07_AUTOMATION/moving_workflow/systemd/*.service"
    },
    %{
      id: "dokumentensystem_ci",
      name: "DokumentenSystem CI Pipeline",
      kind: "EXTERNAL_CI",
      domain: "ci",
      priority: "LOW",
      relative_path: "DokumentenSystem/.github/workflows/ci.yml"
    },
    %{
      id: "email_archive_quality",
      name: "Email Archive Quality",
      kind: "EXTERNAL_CI",
      domain: "ci",
      priority: "LOW",
      relative_path: "DokumentenSystem/.github/workflows/email-archive-quality.yml"
    },
    %{
      id: "sync_evidence_safe_master",
      name: "Sync Evidence Safe Master",
      kind: "EXTERNAL_CI",
      domain: "evidence",
      priority: "LOW",
      relative_path: "DokumentenSystem/.github/workflows/sync-evidence-safe-master.yml"
    },
    %{
      id: "zero_trust_prototype",
      name: "Zero Trust Prototype",
      kind: "EXTERNAL_CI",
      domain: "security",
      priority: "LOW",
      relative_path: "DokumentenSystem/.github/workflows/zero-trust-prototype.yml"
    }
  ]

  @spec snapshot(String.t() | nil) :: map()
  def snapshot(home \\ nil) do
    root = Path.expand(home || System.user_home!())
    fixed_records = Enum.map(@candidates, &resolve(&1, root))
    fixed_paths = known_fixed_paths(root)
    auto_records = discover_folder_records(root, fixed_paths)
    records = fixed_records ++ auto_records

    %{
      status:
        if(Enum.any?(records, &(&1.status == "DISCOVERED")),
          do: "DISCOVERED",
          else: "NOT_CONFIGURED"
        ),
      source_type: "LOCAL_BOUNDED_FOLDER_DISCOVERY",
      synthetic: false,
      real_data: Enum.any?(records, & &1.real_data),
      reachable: Enum.any?(records, & &1.reachable),
      scan_patterns: @scan_patterns,
      max_auto_records: @max_auto_records,
      counts: %{
        total: length(records),
        known_total: length(fixed_records),
        known_discovered: Enum.count(fixed_records, &(&1.status == "DISCOVERED")),
        auto_discovered: length(auto_records),
        discovered: Enum.count(records, &(&1.status == "DISCOVERED")),
        not_configured: Enum.count(records, &(&1.status == "NOT_CONFIGURED"))
      },
      records: records
    }
  end

  defp discover_folder_records(root, fixed_paths) do
    @scan_patterns
    |> Enum.flat_map(fn pattern ->
      root
      |> safe_join(pattern)
      |> Path.wildcard()
    end)
    |> Enum.uniq()
    |> Enum.filter(&regular_file?/1)
    |> Enum.reject(&MapSet.member?(fixed_paths, &1))
    |> Enum.sort()
    |> Enum.take(@max_auto_records)
    |> Enum.map(&auto_record(&1, root))
  end

  defp known_fixed_paths(root) do
    @candidates
    |> Enum.flat_map(fn
      %{relative_path: relative} ->
        path = safe_join(root, relative)
        if regular_file?(path), do: [path], else: []

      %{relative_glob: relative_glob} ->
        root
        |> safe_join(relative_glob)
        |> Path.wildcard()
        |> Enum.filter(&regular_file?/1)
    end)
    |> MapSet.new()
  end

  defp auto_record(path, root) do
    relative = Path.relative_to(path, root)
    {kind, domain, priority} = classify(relative)
    basename = Path.basename(relative)

    %{
      id: "local_" <> stable_id(relative),
      name: friendly_name(basename),
      kind: kind,
      domain: domain,
      priority: priority,
      status: "DISCOVERED",
      real_data: true,
      synthetic: false,
      reachable: true,
      executable: false,
      side_effect_class: "UNKNOWN",
      risk_level: "UNKNOWN",
      integration_mode: "REFERENCE_ONLY",
      discovery_mode: "FOLDER_SCAN",
      runtime_verified: false,
      governance_mapped: false,
      source_ref: relative,
      evidence: [basename]
    }
  end

  defp classify(relative) do
    lower = String.downcase(relative)

    cond do
      String.ends_with?(lower, ".service") ->
        {"SYSTEMD_SERVICE_FILE", infer_domain(lower), "MEDIUM"}

      String.ends_with?(lower, ".timer") ->
        {"SYSTEMD_TIMER_FILE", infer_domain(lower), "MEDIUM"}

      String.contains?(lower, "/.github/workflows/") ->
        {"EXTERNAL_CI", "ci", "LOW"}

      String.ends_with?(lower, ".sh") ->
        {"WORKFLOW_SCRIPT", infer_domain(lower), "MEDIUM"}

      String.ends_with?(lower, ".py") ->
        {"AUTOMATION_SCRIPT", infer_domain(lower), "MEDIUM"}

      String.ends_with?(lower, ".exs") ->
        {"ELIXIR_AUTOMATION", infer_domain(lower), "LOW"}

      true ->
        {"LOCAL_ARTIFACT", infer_domain(lower), "LOW"}
    end
  end

  defp infer_domain(lower) do
    cond do
      contains_any?(lower, ["security", "zero_trust", "zero-trust"]) -> "security"
      contains_any?(lower, ["evidence", "proof"]) -> "evidence"
      contains_any?(lower, ["whatsapp", "telegram", "facebook", "social"]) -> "social"
      contains_any?(lower, ["mail", "email", "gmail"]) -> "email"
      contains_any?(lower, ["backup", "archive"]) -> "backups"
      contains_any?(lower, ["voice", "agent", "ai"]) -> "ai"
      contains_any?(lower, ["document", "dokument", "research", "moving"]) -> "documents"
      true -> "system"
    end
  end

  defp contains_any?(value, needles), do: Enum.any?(needles, &String.contains?(value, &1))

  defp friendly_name(basename) do
    basename
    |> Path.rootname()
    |> String.replace(~r/[-_]+/, " ")
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp stable_id(relative) do
    :crypto.hash(:sha256, relative)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end

  defp resolve(%{relative_path: relative} = candidate, root) do
    path = safe_join(root, relative)
    present = regular_file?(path) or File.dir?(path)

    candidate
    |> base_record(present)
    |> Map.put(:source_ref, relative)
    |> Map.put(:evidence, if(present, do: [Path.basename(path)], else: []))
  end

  defp resolve(%{relative_glob: relative_glob} = candidate, root) do
    glob = safe_join(root, relative_glob)

    evidence =
      glob
      |> Path.wildcard()
      |> Enum.filter(&regular_file?/1)
      |> Enum.map(&Path.basename/1)
      |> Enum.uniq()
      |> Enum.sort()

    candidate
    |> base_record(evidence != [])
    |> Map.put(:source_ref, relative_glob)
    |> Map.put(:evidence, evidence)
  end

  defp base_record(candidate, present) do
    candidate
    |> Map.drop([:relative_path, :relative_glob])
    |> Map.merge(%{
      status: if(present, do: "DISCOVERED", else: "NOT_CONFIGURED"),
      real_data: present,
      synthetic: false,
      reachable: present,
      executable: false,
      side_effect_class: "UNKNOWN",
      risk_level: "UNKNOWN",
      integration_mode: "REFERENCE_ONLY",
      discovery_mode: "FIXED_PATH",
      runtime_verified: false,
      governance_mapped: false
    })
  end

  defp regular_file?(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular}} -> true
      _ -> false
    end
  end

  defp safe_join(root, relative) do
    expanded = Path.expand(relative, root)
    prefix = root <> "/"

    if expanded == root or String.starts_with?(expanded, prefix) do
      expanded
    else
      raise ArgumentError, "integration candidate escaped configured home root"
    end
  end
end
