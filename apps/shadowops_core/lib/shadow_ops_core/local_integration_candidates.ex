defmodule ShadowOpsCore.LocalIntegrationCandidates do
  @moduledoc """
  Read-only discovery for known local workflow/service candidates.

  Every path and glob is fixed in source and resolved beneath the configured home
  root. The module never executes scripts, starts services, expands client input,
  or promotes filesystem presence to READY. Presence proves only DISCOVERED.
  """

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
    records = Enum.map(@candidates, &resolve(&1, root))

    %{
      status: if(Enum.any?(records, &(&1.status == "DISCOVERED")), do: "DISCOVERED", else: "NOT_CONFIGURED"),
      source_type: "LOCAL_FIXED_PATH_DISCOVERY",
      synthetic: false,
      real_data: Enum.any?(records, & &1.real_data),
      reachable: Enum.any?(records, & &1.reachable),
      counts: %{
        total: length(records),
        discovered: Enum.count(records, &(&1.status == "DISCOVERED")),
        not_configured: Enum.count(records, &(&1.status == "NOT_CONFIGURED"))
      },
      records: records
    }
  end

  defp resolve(%{relative_path: relative} = candidate, root) do
    path = safe_join(root, relative)
    present = File.regular?(path) or File.dir?(path)

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
      |> Enum.filter(&File.regular?/1)
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
      integration_mode: "REFERENCE_ONLY"
    })
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
