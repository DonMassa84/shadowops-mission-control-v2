defmodule ShadowOpsCore.KaliNode do
  @moduledoc """
  Bounded, read-only status adapter for the existing Kali security VM.

  The adapter intentionally exposes no free-form SSH execution and no lifecycle
  mutation. Security audits and evidence collection remain governed workflows.
  """

  alias ShadowOpsCore.ConnectorState

  @default_target "kali-vm"
  @domain "kali-2026"
  @capabilities ~w(healthcheck security_audit evidence_collection)

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
    error -> unavailable(@default_target, "KALI_NODE_PROBE_FAILED", Exception.message(error), nil)
  end

  @doc false
  def from_probe(target, {output, 0}, latency_ms) when is_binary(target) and is_binary(output) do
    hostname = String.trim(output)

    if hostname == "" do
      unavailable(target, "KALI_NODE_IDENTITY_EMPTY", "SSH probe returned an empty hostname", latency_ms)
    else
      ConnectorState.build(%{
        id: "node-kali",
        name: "Kali security node",
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

  def from_probe(target, {_output, code}, latency_ms) when is_binary(target) and is_integer(code) do
    unavailable(
      target,
      "KALI_NODE_UNREACHABLE",
      "Authorized Kali SSH status probe failed with exit status #{code}",
      latency_ms
    )
  end

  def from_probe(target, _result, latency_ms) when is_binary(target) do
    unavailable(target, "KALI_NODE_EVIDENCE_INVALID", "Kali status probe evidence was invalid", latency_ms)
  end

  defp unavailable(target, error_code, error_message, latency_ms) do
    ConnectorState.build(%{
      id: "node-kali",
      name: "Kali security node",
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
      domain: @domain,
      transport: "ssh",
      target: target,
      control_actions: ["status"],
      capabilities: @capabilities,
      arbitrary_shell: false,
      arbitrary_systemd: false,
      production_control_plane: false
    }
  end

  defp elapsed(started), do: max(System.monotonic_time(:millisecond) - started, 0)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
