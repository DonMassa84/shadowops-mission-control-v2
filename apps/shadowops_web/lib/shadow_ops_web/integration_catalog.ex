defmodule ShadowOpsWeb.IntegrationCatalog do
  @moduledoc "Evidence-backed catalog projection for ShadowOps production integrations."

  alias ShadowOpsWeb.{RuntimeOverview, SourceRegistry}

  @positive ~w(READY ONLINE CONNECTED AVAILABLE)

  def snapshot do
    overview = RuntimeOverview.snapshot()
    connectors = value(overview, :connectors, %{})

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
        {"Knowledge", value(overview, :knowledge)},
        {"Evidence", value(overview, :evidence)},
        {"Career", value(overview, :career)},
        {"Backups", value(overview, :backups)},
        {"Legal", value(overview, :legal)}
      ]
      |> Enum.map(fn {name, payload} -> card(name, payload, "core") end)

    external =
      connectors
      |> value(:records, [])
      |> Enum.map(fn payload ->
        card(value(payload, :name, value(payload, :id, "Connector")), payload, "external")
      end)

    imports =
      SourceRegistry.all()
      |> Enum.map(fn payload ->
        card(value(payload, :name, value(payload, :id, "Import")), payload, "import")
      end)

    records = core ++ external ++ imports

    %{
      id: "integrations",
      kind: "integration_catalog",
      status: if(Enum.any?(records, &positive?/1), do: "READY", else: "DEGRADED"),
      health: if(Enum.any?(records, &positive?/1), do: "HEALTHY", else: "DEGRADED"),
      source:
        "bounded cached runtime overview + canonical connector adapters + local import evidence",
      source_type: "CONTROL_PLANE_PROJECTION",
      real_data: Enum.any?(records, & &1.real_data),
      synthetic: false,
      reachable: true,
      record_count: length(records),
      core_count: length(core),
      external_count: length(external),
      import_count: length(imports),
      positive_count: Enum.count(records, &positive?/1),
      records: records
    }
  end

  def positive?(card), do: card.status in @positive

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
