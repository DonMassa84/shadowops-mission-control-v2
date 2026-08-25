defmodule ShadowOpsCore.Node do
  @moduledoc """
  Canonical node semantics shared by runtime and web projections.

  Physical node discovery remains the responsibility of runtime adapters. Logical
  project nodes are normalized here so UI and controllers do not encode provider-
  specific readiness or control rules.
  """

  alias ShadowOpsCore.Truthfulness

  @type kind :: :physical | :logical_project
  @type provider :: :local | :ssh | :chatgpt | atom()

  @spec logical_project(map(), String.t() | nil, provider()) :: map()
  def logical_project(project, generated_at, provider \\ :chatgpt) when is_map(project) do
    ready = Truthfulness.ready?(project)
    status = Truthfulness.normalize_ready_state(project)
    project_id = value(project, :id)

    %{
      id: project_id,
      node_id: project_id,
      name: value(project, :name) || project_id,
      kind: "logical_project_node",
      status: status,
      health: if(ready, do: "HEALTHY", else: "UNAVAILABLE"),
      availability: if(ready, do: "AVAILABLE", else: "UNAVAILABLE"),
      source: "federated #{provider_label(provider)} project catalog",
      source_type:
        provider |> provider_label() |> String.upcase() |> Kernel.<>("_LIBRARY_PROJECT"),
      real_data: ready,
      synthetic: false,
      enabled: true,
      reachable: ready,
      optional: true,
      load: nil,
      ram: nil,
      uptime_seconds: nil,
      last_sync_at: generated_at,
      last_success_at: if(ready, do: generated_at),
      latency_ms: nil,
      record_count: nil,
      updated_at: generated_at,
      error_code: if(ready, do: nil, else: not_configured_code(provider)),
      error_message: if(ready, do: nil, else: not_configured_message(provider)),
      metadata: %{
        logical: true,
        provider: Atom.to_string(provider),
        control_actions: ["status"],
        integration_mode: value(project, :integration_mode),
        content_ingested: value(project, :content_ingested) == true
      }
    }
  end

  @spec logical?(map()) :: boolean()
  def logical?(node) when is_map(node), do: get_in(node, [:metadata, :logical]) == true
  def logical?(_), do: false

  @spec provider(map()) :: atom() | nil
  def provider(node) when is_map(node) do
    case get_in(node, [:metadata, :provider]) do
      value when is_atom(value) -> value
      "chatgpt" -> :chatgpt
      "local" -> :local
      "ssh" -> :ssh
      _ -> nil
    end
  end

  def provider(_), do: nil

  @spec action_allowed?(map(), String.t() | atom()) :: boolean()
  def action_allowed?(node, action) when is_map(node) do
    action = to_string(action)

    if logical?(node) do
      action in get_in(node, [:metadata, :control_actions])
    else
      true
    end
  end

  def action_allowed?(_node, _action), do: false

  @spec id(map()) :: term()
  def id(node) when is_map(node), do: Map.get(node, :node_id) || Map.get(node, :id)
  def id(_), do: nil

  defp provider_label(provider), do: provider |> Atom.to_string() |> String.downcase()

  defp not_configured_code(provider),
    do: provider |> provider_label() |> String.upcase() |> Kernel.<>("_PROJECT_NOT_CONFIGURED")

  defp not_configured_message(provider),
    do: "No evidenced local #{provider_label(provider)} project export is available for this node"

  defp value(record, key), do: Map.get(record, key, Map.get(record, to_string(key)))
end
