defmodule ShadowOpsCore.ProjectCatalogSeed do
  @moduledoc """
  Repository-safe discovery seed for known ShadowOps project/workstream identities.

  Seed records are metadata-only and deliberately non-positive. They exist so the
  local Project Catalog can expose known workstreams without claiming that a local
  repository, runtime, connector, or ChatGPT export is currently reachable.
  Existing evidenced catalog records always win over seed records with the same id.
  """

  alias ShadowOpsCore.ProjectCatalog

  @seed_source "handoff_project"

  @projects [
    {"shadowops:mission-control-v2", "ShadowOps Mission Control V2", "shadowops", "DISCOVERED"},
    {"shadowops:data-fabric", "ShadowOps Data Fabric", "shadowops", "DISCOVERED"},
    {"shadowops:ontology-v3", "ShadowOps Ontology v3", "shadowops", "DISCOVERED"},
    {"shadowops:electron-mission-control", "Electron Mission Control", "shadowops", "DISCOVERED"},
    {"shadowops:workflow-federation", "Workflow Federation", "shadowops", "DISCOVERED"},
    {"shadowops:whatsapp-agent", "WhatsApp Agent", "social", "DISCOVERED"},
    {"shadowops:facebook-analytics", "Facebook Analytics", "social", "DISCOVERED"},
    {"shadowops:messenger", "Messenger", "social", "DISCOVERED"},
    {"shadowops:telegram-controller", "Telegram Workflow Controller", "social", "DISCOVERED"},
    {"shadowops:local-ai", "Local AI / Ollama", "ai", "DISCOVERED"},
    {"shadowops:i7-control", "i7 Control", "ops", "DISCOVERED"},
    {"shadowops:knowledge", "Knowledge", "knowledge", "DISCOVERED"},
    {"shadowops:evidence", "Evidence", "evidence", "DISCOVERED"},
    {"shadowops:career", "Career", "career", "DISCOVERED"},
    {"shadowops:backups", "Backups", "backup", "DISCOVERED"},
    {"shadowops:reporting", "Reporting", "reporting", "DISCOVERED"},
    {"shadowops:opencode-standard", "OpenCode Standard", "ops", "DISCOVERED"},
    {"ihk:zero-trust-project", "IHK Zero Trust Project", "ihk", "DISCOVERED"},
    {"chatgpt:local-project", "ChatGPT Local Project Source", "shadowops", "NOT_CONFIGURED"}
  ]

  @spec projects() :: [map()]
  def projects do
    Enum.map(@projects, fn {id, name, domain, status} ->
      ProjectCatalog.normalize_project(%{
        "id" => id,
        "name" => name,
        "domain" => domain,
        "source_type" => @seed_source,
        "status" => status,
        "visibility" => "PRIVATE_LOCAL",
        "real_data" => false,
        "synthetic" => false,
        "reachable" => false,
        "content_ingested" => false,
        "integration_mode" => "REFERENCE_ONLY"
      })
    end)
  end

  @doc "Merges seed records without replacing existing evidence for the same stable id."
  @spec merge([map()]) :: [map()]
  def merge(existing) when is_list(existing) do
    normalized_existing =
      existing
      |> Enum.map(&ProjectCatalog.normalize_project/1)
      |> Enum.reject(&is_nil/1)

    existing_ids = MapSet.new(normalized_existing, & &1.id)

    supplements = Enum.reject(projects(), &MapSet.member?(existing_ids, &1.id))

    (normalized_existing ++ supplements)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.id)
  end

  @spec payload([map()], String.t() | nil, String.t()) :: map()
  def payload(existing, github_discovery_mode \\ nil, generated_at \\ now_iso8601()) do
    %{
      schema_version: 1,
      generated_at: generated_at,
      github_discovery_mode: github_discovery_mode || "UNKNOWN",
      synthetic: false,
      projects: merge(existing)
    }
  end

  defp now_iso8601, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
