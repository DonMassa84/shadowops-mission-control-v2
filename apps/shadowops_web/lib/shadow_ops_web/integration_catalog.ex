defmodule ShadowOpsWeb.IntegrationCatalog do
  @moduledoc "Evidence-backed catalog projection for ShadowOps production integrations."

  alias ShadowOpsCore.{LocalIntegrationCandidates, LocalWorkflowRegistry, WorkflowCuration}
  alias ShadowOpsWeb.{RuntimeOverview, SourceRegistry}

  @positive ~w(READY ONLINE CONNECTED AVAILABLE)
  @required_core_names MapSet.new([
                         "System",
                         "Workflows",
                         "Runs",
                         "Services",
                         "Nodes",
                         "AI / Models",
                         "Approvals",
                         "Audit",
                         "Security"
                       ])

  def snapshot do
    overview = RuntimeOverview.snapshot()
    connectors = value(overview, :connectors, %{})
    local_discovery = LocalIntegrationCandidates.snapshot()
    local_workflows = LocalWorkflowRegistry.snapshot()
    workflow_curation = WorkflowCuration.snapshot(local_workflows)
    knowledge = value(overview, :knowledge, %{})
    knowledge_sources = knowledge_sources(knowledge)

    core =
      [
        {"System", value(overview, :system)},
        {"Workflows", value(overview, :workflows)},
        {"Runs", value(overview, :runs)},
        {"Services", value(overview, :services)},
        {"Nodes", value(overview, :nodes)},
        {"Agents", value(overview, :agents)},
        {"AI / Models", value(overview, :ai)},
        {"Approvals", value(overview, :approvals)},
        {"Audit", value(overview, :audit)},
        {"Security", value(overview, :security)},
        {"Knowledge", knowledge},
        {"Evidence", value(overview, :evidence)},
        {"Career", value(overview, :career)},
        {"Backups", value(overview, :backups)},
        {"Legal", value(overview, :legal)}
      ]
      |> Enum.map(fn {name, payload} -> card(name, payload, "core") end)

    external =
      connectors
      |> value(:records, [])
      |> Enum.reject(&retired_local_llm_connector?/1)
      |> Enum.map(fn payload ->
        card(value(payload, :name, value(payload, :id, "Connector")), payload, "external")
      end)

    imports =
      SourceRegistry.all()
      |> Enum.map(fn payload ->
        card(value(payload, :name, value(payload, :id, "Import")), payload, "import")
      end)

    local = [local_card(local_discovery)]

    records = core ++ external ++ imports ++ local
    health = health_summary(records)

    %{
      id: "integrations",
      kind: "integration_catalog",
      status: health.status,
      health: health.health,
      source:
        "bounded cached runtime overview + canonical connector adapters + local import evidence + bounded local folder discovery + stable local workflow evidence registry + curated workflow readiness funnel + measured local knowledge sources",
      source_type: "CONTROL_PLANE_PROJECTION",
      real_data: Enum.any?(records, & &1.real_data),
      synthetic: false,
      reachable: health.required_ready == health.required_total and health.required_total > 0,
      record_count: length(records),
      core_count: length(core),
      external_count: length(external),
      import_count: length(imports),
      local_count: length(local),
      local_discovered_count: local_discovery.counts.discovered,
      local_auto_discovered_count: local_discovery.counts.auto_discovered,
      local_workflow_registered_count: local_workflows.counts.registered,
      local_workflow_rejected_count: local_workflows.counts.rejected,
      local_workflow_registry: local_workflows,
      workflow_found_count: workflow_curation.counts.found,
      workflow_unique_count: workflow_curation.counts.unique,
      workflow_potential_duplicate_count: workflow_curation.counts.potential_duplicates,
      workflow_duplicate_group_count: workflow_curation.counts.duplicate_groups,
      workflow_normalized_count: workflow_curation.counts.normalized,
      workflow_connected_count: workflow_curation.counts.connected,
      workflow_tested_count: workflow_curation.counts.tested,
      workflow_production_ready_count: workflow_curation.counts.production_ready,
      workflow_curation: workflow_curation,
      knowledge_source_count: length(knowledge_sources),
      knowledge_available_source_count:
        Enum.count(knowledge_sources, &(&1.availability == "AVAILABLE")),
      knowledge_document_count: Enum.sum(Enum.map(knowledge_sources, & &1.document_count)),
      knowledge_indexed_document_count: value(knowledge, :indexed_documents_count),
      knowledge_sources: knowledge_sources,
      positive_count: Enum.count(records, &positive?/1),
      required_core_count: health.required_total,
      required_core_ready_count: health.required_ready,
      optional_count: health.optional_total,
      optional_ready_count: health.optional_ready,
      local_discovery: local_discovery,
      records: records
    }
  end

  def positive?(%{scope: scope} = card) when scope in ["external", "import", "local"],
    do: card.status in @positive and card.real_data == true and card.reachable == true

  def positive?(card), do: card.status in @positive

  @doc false
  def health_summary(records) when is_list(records) do
    {required, optional} = Enum.split_with(records, &required_core?/1)
    required_ready = Enum.count(required, &positive?/1)
    optional_ready = Enum.count(optional, &positive?/1)
    required_total = length(required)

    status =
      cond do
        required_total == 0 -> "UNAVAILABLE"
        required_ready == required_total -> "READY"
        required_ready > 0 -> "DEGRADED"
        true -> "UNAVAILABLE"
      end

    %{
      status: status,
      health: if(status == "READY", do: "HEALTHY", else: status),
      required_total: required_total,
      required_ready: required_ready,
      optional_total: length(optional),
      optional_ready: optional_ready
    }
  end

  defp local_card(local_discovery) do
    %{
      id: "local-functions",
      name: "Local Functions",
      scope: "local",
      kind: "local_function_inventory",
      status: local_discovery.status,
      health: if(local_discovery.status == "DISCOVERED", do: "DISCOVERED", else: "UNKNOWN"),
      source: "bounded scan of known local automation folders",
      source_type: local_discovery.source_type,
      real_data: local_discovery.real_data,
      synthetic: false,
      reachable: local_discovery.reachable,
      record_count: local_discovery.counts.discovered,
      last_sync: nil,
      domains:
        local_discovery.records
        |> Enum.filter(&(&1.status == "DISCOVERED"))
        |> Enum.map(& &1.domain)
        |> Enum.uniq()
        |> Enum.sort(),
      secret_binding: nil,
      error_code: nil,
      error_message: nil
    }
  end

  defp knowledge_sources(knowledge) do
    knowledge
    |> value(:sources, [])
    |> Enum.map(fn source ->
      name = to_string(value(source, :source, "Knowledge source"))

      %{
        id: slug(name),
        name: name,
        availability: normalize_status(value(source, :availability, "UNKNOWN")),
        document_count: integer_or_zero(value(source, :document_count)),
        last_update: value(source, :last_update),
        source_type: knowledge_source_type(name),
        synthetic: false
      }
    end)
  end

  defp knowledge_source_type("ProofFlow-Obsidian-Vault"), do: "LOCAL_KNOWLEDGE_VAULT"
  defp knowledge_source_type("shadowops-knowledge"), do: "LOCAL_KNOWLEDGE_STORE"
  defp knowledge_source_type("workflow-knowledge"), do: "WORKFLOW_KNOWLEDGE_STORE"
  defp knowledge_source_type(_), do: "LOCAL_KNOWLEDGE_SOURCE"

  defp integer_or_zero(value) when is_integer(value) and value >= 0, do: value
  defp integer_or_zero(_), do: 0

  defp required_core?(%{scope: "core", name: name}),
    do: MapSet.member?(@required_core_names, name)

  defp required_core?(_), do: false

  defp retired_local_llm_connector?(payload) do
    payload
    |> connector_identity()
    |> String.contains?("ollama")
  end

  defp connector_identity(payload) do
    [value(payload, :id), value(payload, :name), value(payload, :kind)]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(" ", &to_string/1)
    |> String.downcase()
  end

  defp card(name, payload, scope) when is_map(payload) do
    %{
      id: to_string(value(payload, :id, slug(name))),
      name: to_string(name),
      scope: scope,
      kind: to_string(value(payload, :kind, "module")),
      status:
        normalize_status(
          value(payload, :status) || value(payload, :state) || value(payload, :overall) ||
            value(payload, :availability) || "UNKNOWN"
        ),
      health: normalize_status(value(payload, :health, "UNKNOWN")),
      source: value(payload, :source, "internal control-plane state"),
      source_type: value(payload, :source_type, "INTERNAL"),
      real_data: value(payload, :real_data, false) == true,
      synthetic: value(payload, :synthetic, false) == true,
      reachable: value(payload, :reachable, false) == true,
      record_count: value(payload, :record_count, value(payload, :count)),
      last_sync: value(payload, :last_sync),
      domains: value(payload, :domains, []),
      secret_binding: value(payload, :secret_binding),
      error_code: value(payload, :error_code),
      error_message: value(payload, :error_message)
    }
  end

  defp card(name, _payload, scope) do
    %{
      id: slug(name),
      name: to_string(name),
      scope: scope,
      kind: "module",
      status: "UNAVAILABLE",
      health: "UNKNOWN",
      source: "no evidence",
      source_type: "UNKNOWN",
      real_data: false,
      synthetic: false,
      reachable: false,
      record_count: nil,
      last_sync: nil,
      domains: [],
      secret_binding: nil,
      error_code: "NO_EVIDENCE",
      error_message: "No source-backed state is available"
    }
  end

  defp normalize_status(nil), do: "UNKNOWN"
  defp normalize_status(value), do: value |> to_string() |> String.upcase()

  defp slug(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp value(map, key, default \\ nil)

  defp value(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp value(_map, _key, default), do: default
end
