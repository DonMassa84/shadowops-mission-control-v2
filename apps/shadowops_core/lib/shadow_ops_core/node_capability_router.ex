defmodule ShadowOpsCore.NodeCapabilityRouter do
  @moduledoc """
  Evidence-backed node selection for bounded ShadowOps workloads.

  A node is selectable only when current runtime evidence marks it READY/ONLINE,
  reachable, real and non-synthetic, and the requested capability appears in its
  `verified_capabilities` metadata. Declared capabilities alone never make a node
  executable.

  Security and forensics workloads prefer Kali. AI workloads prefer the Ryzen host,
  then the i7 node. QA/repository workloads prefer i7 and may fall back to Ryzen only
  when the same capability is independently verified there.
  """

  alias ShadowOpsCore.{I7Node, RuntimeSources}

  @security_capabilities ~w(
    security_audit
    evidence_collection
    network_discovery
    service_exposure_audit
    http_security_audit
    tls_audit
    dns_audit
    ssh_posture_audit
    host_hardening_audit
    package_audit
    dependency_audit
    sbom_analysis
    secrets_scan
    malware_scan
    yara_scan
    forensic_triage
    log_analysis
    pcap_analysis
    file_hashing
    integrity_check
    attack_surface_inventory
    vulnerability_assessment
    container_security_audit
    web_passive_assessment
  )

  @active_assessment_capabilities ~w(
    network_discovery
    service_exposure_audit
    vulnerability_assessment
    attack_surface_inventory
  )

  @ai_capabilities ~w(ai_inference gpu_inference local_ai)
  @qa_capabilities ~w(qa repository_change supplementary_compute)
  @blocked_capabilities ~w(arbitrary_shell arbitrary_systemd production_control_plane)
  @routable_capabilities @security_capabilities ++ @ai_capabilities ++ @qa_capabilities

  @doc "Routes a capability using the current runtime node projection."
  def route_live(capability, context \\ %{}) when is_binary(capability) and is_map(context) do
    nodes =
      RuntimeSources.nodes()
      |> Map.get(:records, [])
      |> Enum.reject(&(node_id(&1) == "i7"))
      |> Kernel.++([I7Node.status()])
      |> enrich_ai_evidence(RuntimeSources.ai())

    route(capability, nodes, context)
  end

  @doc "Routes a capability over an explicit node collection."
  def route(capability, nodes, context \\ %{})

  def route(capability, nodes, context)
      when is_binary(capability) and is_list(nodes) and is_map(context) do
    with :ok <- capability_allowed(capability),
         :ok <- target_guard(capability, context),
         :ok <- approval_guard(context) do
      select(capability, nodes)
    end
  end

  def route(_capability, _nodes, _context), do: {:error, :invalid_route_request}

  @doc "Returns true only when a node has current verified evidence for a capability."
  def eligible?(node, capability) when is_map(node) and is_binary(capability) do
    status = value(node, :status)
    metadata = value(node, :metadata) || %{}
    verified = value(metadata, :verified_capabilities) || []

    status in ["READY", "ONLINE"] and value(node, :reachable) == true and
      value(node, :real_data) == true and value(node, :synthetic) == false and
      capability in verified
  end

  def eligible?(_, _), do: false

  defp capability_allowed(capability) when capability in @blocked_capabilities,
    do: {:error, :capability_not_routable}

  defp capability_allowed(capability) when capability in @routable_capabilities, do: :ok
  defp capability_allowed(_capability), do: {:error, :unsupported_capability}

  defp target_guard(capability, context) when capability in @active_assessment_capabilities do
    if value(context, :target_authorized) == true,
      do: :ok,
      else: {:error, :target_not_authorized}
  end

  defp target_guard(_capability, _context), do: :ok

  defp approval_guard(context) do
    risk = value(context, :risk_level) || "L0"

    case risk do
      level when level in ["L0", "L1"] ->
        :ok

      level when level in ["L2", "L3"] ->
        if value(context, :approval_status) in [:consumed, "CONSUMED"],
          do: :ok,
          else: {:error, :approval_required}

      _ ->
        {:error, :invalid_risk_level}
    end
  end

  defp select(capability, nodes) do
    preferences = preference(capability)

    candidates =
      preferences
      |> Enum.map(fn node_id -> Enum.find(nodes, &(node_id(&1) == node_id)) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&eligible?(&1, capability))

    case candidates do
      [selected | _] ->
        selected_id = node_id(selected)

        {:ok,
         %{
           node_id: selected_id,
           capability: capability,
           preferred_node: List.first(preferences),
           fallback: selected_id != List.first(preferences),
           evidence: capability_evidence(selected, capability)
         }}

      [] ->
        {:error, :no_verified_executor}
    end
  end

  defp preference(capability) when capability in @security_capabilities,
    do: ["kali", "local-ryzen", "i7"]

  defp preference(capability) when capability in @ai_capabilities,
    do: ["local-ryzen", "i7", "kali"]

  defp preference(capability) when capability in @qa_capabilities,
    do: ["i7", "local-ryzen", "kali"]

  defp capability_evidence(node, capability) do
    metadata = value(node, :metadata) || %{}

    %{
      source: value(metadata, :capability_evidence_source),
      verified_at: value(metadata, :capability_evidence_at),
      capability: capability,
      synthetic: value(node, :synthetic)
    }
  end

  defp enrich_ai_evidence(nodes, ai) do
    ai_records = Map.get(ai, :records, [])

    Enum.map(nodes, fn node ->
      id = node_id(node)

      verified_ai =
        Enum.any?(ai_records, fn runtime ->
          value(runtime, :node) == id and value(runtime, :status) in ["READY", "ONLINE"] and
            value(runtime, :reachable) == true and value(runtime, :real_data) == true and
            value(runtime, :synthetic) == false
        end)

      if verified_ai do
        put_verified_capability(node, "ai_inference", "verified AI runtime inventory")
      else
        node
      end
    end)
  end

  defp put_verified_capability(node, capability, source) do
    metadata = value(node, :metadata) || %{}
    current = value(metadata, :verified_capabilities) || []

    metadata =
      metadata
      |> Map.put(:verified_capabilities, Enum.uniq(current ++ [capability]))
      |> Map.put(:capability_evidence_source, source)

    Map.put(node, :metadata, metadata)
  end

  defp node_id(node), do: value(node, :node_id) || value(node, :id)

  defp value(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp value(_, _), do: nil
end
