defmodule ShadowOpsCore.KaliNode do
  @moduledoc """
  Bounded status adapter and capability profile for the existing Kali security VM.

  Kali is the preferred ShadowOps node for defensive security, network analysis,
  vulnerability assessment and forensic workloads. Capabilities are descriptive
  until a governed workflow supplies current runtime/tool evidence. The adapter
  intentionally exposes no free-form SSH execution and no lifecycle mutation.
  """

  alias ShadowOpsCore.ConnectorState

  @default_target "kali-vm"
  @domain "kali-2026"

  @capabilities ~w(
    healthcheck
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

  @preferred_workloads ~w(
    security
    network_security
    vulnerability_management
    digital_forensics
    incident_response
    evidence_validation
    attack_surface_review
    protocol_analysis
    hardening_review
  )

  def status do
    target = System.get_env("SHADOWOPS_KALI_SSH_HOST", @default_target)
    started = System.monotonic_time(:millisecond)

    result =
      System.cmd(
        "ssh",
        ["-o", "BatchMode=yes", "-o", "ConnectTimeout=3", target, "hostname"],
        stderr_to_stdout: true
      )

    from_probe(target, result, elapsed(started))
  rescue
    error ->
      unavailable(
        @default_target,
        "KALI_NODE_PROBE_FAILED",
        Exception.message(error),
        nil
      )
  end

  @doc false
  def from_probe(target, {output, 0}, latency_ms) when is_binary(target) and is_binary(output) do
    hostname = String.trim(output)

    if hostname == "" do
      unavailable(
        target,
        "KALI_NODE_IDENTITY_EMPTY",
        "SSH probe returned an empty hostname",
        latency_ms
      )
    else
      ConnectorState.build(%{
        id: "node-kali",
        name: "Kali security & forensics node",
        kind: "node",
        status: "READY",
        health: "HEALTHY",
        source: "ssh #{target} -- hostname",
        source_type: "AUTHORIZED_SSH_PROBE",
        real_data: true,
        synthetic: false,
        enabled: true,
        reachable: true,
        latency_ms: latency_ms,
        last_success_at: now(),
        metadata: metadata(target)
      })
      |> ConnectorState.attach(%{
        node_id: "kali",
        hostname: hostname,
        load: nil,
        ram: nil,
        uptime_seconds: nil,
        services: []
      })
    end
  end

  def from_probe(target, {_output, code}, latency_ms)
      when is_binary(target) and is_integer(code) do
    unavailable(
      target,
      "KALI_NODE_UNREACHABLE",
      "Authorized Kali SSH status probe failed with exit status #{code}",
      latency_ms
    )
  end

  def from_probe(target, _result, latency_ms) when is_binary(target) do
    unavailable(
      target,
      "KALI_NODE_EVIDENCE_INVALID",
      "Kali status probe evidence was invalid",
      latency_ms
    )
  end

  defp unavailable(target, error_code, error_message, latency_ms) do
    ConnectorState.build(%{
      id: "node-kali",
      name: "Kali security & forensics node",
      kind: "node",
      status: "OPTIONAL_UNAVAILABLE",
      health: "UNAVAILABLE",
      source: "ssh #{target} -- hostname",
      source_type: "AUTHORIZED_SSH_PROBE",
      real_data: false,
      synthetic: false,
      enabled: true,
      reachable: false,
      latency_ms: latency_ms,
      error_code: error_code,
      error_message: error_message,
      metadata: metadata(target)
    })
    |> ConnectorState.attach(%{
      node_id: "kali",
      hostname: nil,
      load: nil,
      ram: nil,
      uptime_seconds: nil,
      services: []
    })
  end

  defp metadata(target) do
    %{
      role: "security_node",
      specialization: "security_forensics",
      scheduler_priority: "preferred_for_matching_capability",
      domain: @domain,
      transport: "ssh",
      target: target,
      control_actions: ["status"],
      capabilities: @capabilities,
      preferred_workloads: @preferred_workloads,
      capability_activation: "requires_current_runtime_tool_evidence",
      execution_policy: "bounded_workflows_only",
      target_policy: "owned_or_explicitly_authorized_scope_only",
      active_assessment_approval: "required_when_risk_is_l2_or_higher",
      arbitrary_shell: false,
      arbitrary_systemd: false,
      production_control_plane: false
    }
  end

  defp elapsed(started), do: max(System.monotonic_time(:millisecond) - started, 0)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
