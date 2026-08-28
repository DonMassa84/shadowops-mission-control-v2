defmodule ShadowOpsCore.KaliNode do
  @moduledoc """
  Bounded status adapter and evidence-backed capability profile for the existing Kali security VM.

  Kali is the preferred ShadowOps node for defensive security, network analysis,
  vulnerability assessment and forensic workloads. Declared capabilities never become
  routable by declaration alone: the adapter verifies a fixed allow-list of security tools
  through a bounded SSH probe and exposes only capabilities supported by current evidence.

  The adapter intentionally exposes no free-form SSH execution and no lifecycle mutation.
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

  @tool_names ~w(
    nmap
    curl
    openssl
    dig
    ssh
    dpkg
    apt-cache
    sha256sum
    file
    stat
    grep
    jq
    tshark
    yara
    clamscan
    gitleaks
    trufflehog
    trivy
    syft
    grype
    lynis
  )

  @tool_probe_command "for tool in #{Enum.join(@tool_names, " ")}; do if command -v \"$tool\" >/dev/null 2>&1; then printf '%s=1\\n' \"$tool\"; else printf '%s=0\\n' \"$tool\"; fi; done"

  def status do
    target = System.get_env("SHADOWOPS_KALI_SSH_HOST", @default_target)
    started = System.monotonic_time(:millisecond)

    identity_result = ssh(target, "hostname")

    tool_result =
      case identity_result do
        {output, 0} when is_binary(output) ->
          if String.trim(output) == "", do: :not_run, else: ssh(target, @tool_probe_command)

        _ ->
          :not_run
      end

    from_probe(target, identity_result, elapsed(started), tool_result)
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
  def from_probe(target, result, latency_ms),
    do: from_probe(target, result, latency_ms, :not_run)

  @doc false
  def from_probe(target, {output, 0}, latency_ms, tool_result)
      when is_binary(target) and is_binary(output) do
    hostname = String.trim(output)

    if hostname == "" do
      unavailable(
        target,
        "KALI_NODE_IDENTITY_EMPTY",
        "SSH probe returned an empty hostname",
        latency_ms
      )
    else
      evidence = capability_evidence(tool_result)

      ConnectorState.build(%{
        id: "node-kali",
        name: "Kali security & forensics node",
        kind: "node",
        status: "READY",
        health: "HEALTHY",
        source: "ssh #{target} -- bounded identity/tool probes",
        source_type: "AUTHORIZED_SSH_PROBE",
        real_data: true,
        synthetic: false,
        enabled: true,
        reachable: true,
        latency_ms: latency_ms,
        last_success_at: now(),
        metadata: metadata(target, evidence)
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

  def from_probe(target, {_output, code}, latency_ms, _tool_result)
      when is_binary(target) and is_integer(code) do
    unavailable(
      target,
      "KALI_NODE_UNREACHABLE",
      "Authorized Kali SSH status probe failed with exit status #{code}",
      latency_ms
    )
  end

  def from_probe(target, _result, latency_ms, _tool_result) when is_binary(target) do
    unavailable(
      target,
      "KALI_NODE_EVIDENCE_INVALID",
      "Kali status probe evidence was invalid",
      latency_ms
    )
  end

  @doc false
  def verified_capabilities(tool_names) when is_list(tool_names) do
    tools = MapSet.new(tool_names)

    ["healthcheck"]
    |> maybe_add("security_audit", all?(tools, ~w(nmap curl openssl)))
    |> maybe_add("evidence_collection", all?(tools, ~w(sha256sum file stat)))
    |> maybe_add("network_discovery", present?(tools, "nmap"))
    |> maybe_add("service_exposure_audit", present?(tools, "nmap"))
    |> maybe_add("http_security_audit", present?(tools, "curl"))
    |> maybe_add("tls_audit", present?(tools, "openssl"))
    |> maybe_add("dns_audit", present?(tools, "dig"))
    |> maybe_add("ssh_posture_audit", present?(tools, "ssh"))
    |> maybe_add("host_hardening_audit", present?(tools, "lynis"))
    |> maybe_add("package_audit", all?(tools, ["dpkg", "apt-cache"]))
    |> maybe_add("dependency_audit", any?(tools, ~w(trivy grype)))
    |> maybe_add("sbom_analysis", any?(tools, ~w(syft trivy)))
    |> maybe_add("secrets_scan", any?(tools, ~w(gitleaks trufflehog)))
    |> maybe_add("malware_scan", present?(tools, "clamscan"))
    |> maybe_add("yara_scan", present?(tools, "yara"))
    |> maybe_add("forensic_triage", all?(tools, ~w(file stat sha256sum)))
    |> maybe_add("log_analysis", all?(tools, ~w(grep jq)))
    |> maybe_add("pcap_analysis", present?(tools, "tshark"))
    |> maybe_add("file_hashing", present?(tools, "sha256sum"))
    |> maybe_add("integrity_check", present?(tools, "sha256sum"))
    |> maybe_add("attack_surface_inventory", present?(tools, "nmap"))
    |> maybe_add("vulnerability_assessment", present?(tools, "nmap"))
    |> maybe_add("container_security_audit", present?(tools, "trivy"))
    |> maybe_add("web_passive_assessment", present?(tools, "curl"))
  end

  defp ssh(target, command) do
    System.cmd(
      "ssh",
      ["-o", "BatchMode=yes", "-o", "ConnectTimeout=3", target, command],
      stderr_to_stdout: true
    )
  end

  defp capability_evidence({output, 0}) when is_binary(output) do
    present = parse_tool_probe(output)

    %{
      status: "VERIFIED",
      tools_present: present,
      verified_capabilities: verified_capabilities(present),
      source: "bounded SSH command -v allow-list probe",
      verified_at: now()
    }
  end

  defp capability_evidence({_output, code}) when is_integer(code) do
    %{
      status: "UNAVAILABLE",
      tools_present: [],
      verified_capabilities: ["healthcheck"],
      source: "bounded SSH command -v allow-list probe failed with exit status #{code}",
      verified_at: now()
    }
  end

  defp capability_evidence(_) do
    %{
      status: "NOT_RUN",
      tools_present: [],
      verified_capabilities: ["healthcheck"],
      source: "identity evidence only",
      verified_at: now()
    }
  end

  defp parse_tool_probe(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reduce([], fn line, acc ->
      case String.split(line, "=", parts: 2) do
        [tool, "1"] when tool in @tool_names -> [tool | acc]
        _ -> acc
      end
    end)
    |> Enum.reverse()
  end

  defp unavailable(target, error_code, error_message, latency_ms) do
    evidence = %{
      status: "UNAVAILABLE",
      tools_present: [],
      verified_capabilities: [],
      source: "no current Kali runtime evidence",
      verified_at: nil
    }

    ConnectorState.build(%{
      id: "node-kali",
      name: "Kali security & forensics node",
      kind: "node",
      status: "OPTIONAL_UNAVAILABLE",
      health: "UNAVAILABLE",
      source: "ssh #{target} -- bounded identity/tool probes",
      source_type: "AUTHORIZED_SSH_PROBE",
      real_data: false,
      synthetic: false,
      enabled: true,
      reachable: false,
      latency_ms: latency_ms,
      error_code: error_code,
      error_message: error_message,
      metadata: metadata(target, evidence)
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

  defp metadata(target, evidence) do
    %{
      role: "security_node",
      specialization: "security_forensics",
      scheduler_priority: "preferred_for_matching_capability",
      domain: @domain,
      transport: "ssh",
      target: target,
      control_actions: ["status"],
      capabilities: @capabilities,
      verified_capabilities: evidence.verified_capabilities,
      preferred_workloads: @preferred_workloads,
      capability_activation: "requires_current_runtime_tool_evidence",
      capability_evidence_status: evidence.status,
      capability_evidence_source: evidence.source,
      capability_evidence_at: evidence.verified_at,
      verified_tools: evidence.tools_present,
      execution_policy: "bounded_workflows_only",
      target_policy: "owned_or_explicitly_authorized_scope_only",
      active_assessment_approval: "required_when_risk_is_l2_or_higher",
      arbitrary_shell: false,
      arbitrary_systemd: false,
      production_control_plane: false
    }
  end

  defp maybe_add(capabilities, capability, true), do: capabilities ++ [capability]
  defp maybe_add(capabilities, _capability, false), do: capabilities
  defp present?(tools, tool), do: MapSet.member?(tools, tool)
  defp all?(tools, required), do: Enum.all?(required, &present?(tools, &1))
  defp any?(tools, required), do: Enum.any?(required, &present?(tools, &1))
  defp elapsed(started), do: max(System.monotonic_time(:millisecond) - started, 0)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
