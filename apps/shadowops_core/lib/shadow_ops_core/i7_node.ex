defmodule ShadowOpsCore.I7Node do
  @moduledoc """
  Evidence-backed adapter for the dedicated i7 QA/supplementary-compute node.

  The adapter uses only a fixed SSH target and a fixed read-only probe. Declared
  capabilities never become routable without current runtime evidence.
  """

  alias ShadowOpsCore.ConnectorState

  @target "shadowserver-i7"
  @probe "printf 'hostname='; hostname; printf 'cpus='; nproc; printf 'mix='; command -v mix >/dev/null 2>&1 && echo 1 || echo 0; printf 'git='; command -v git >/dev/null 2>&1 && echo 1 || echo 0; printf 'workspace='; test -d \"$HOME/Projects/shadowops-mission-control-v2/.git\" && echo 1 || echo 0"

  def status do
    started = System.monotonic_time(:millisecond)

    result =
      System.cmd(
        "ssh",
        ["-o", "BatchMode=yes", "-o", "ConnectTimeout=3", @target, @probe],
        stderr_to_stdout: true
      )

    from_probe(result, elapsed(started))
  rescue
    error -> unavailable("I7_NODE_PROBE_FAILED", Exception.message(error), nil)
  end

  @doc false
  def from_probe({output, 0}, latency_ms) when is_binary(output) do
    evidence = parse_probe(output)

    if valid_identity?(evidence) do
      capabilities = verified_capabilities(evidence)

      ConnectorState.build(%{
        id: "node-i7",
        name: "i7 QA & supplementary compute node",
        kind: "node",
        status: "READY",
        health: "HEALTHY",
        source: "bounded SSH identity/tool/workspace probe",
        source_type: "AUTHORIZED_SSH_PROBE",
        real_data: true,
        synthetic: false,
        enabled: true,
        reachable: true,
        latency_ms: latency_ms,
        last_success_at: now(),
        metadata: %{
          role: "qa_supplementary_compute",
          scheduler_priority: "preferred_for_qa_compute",
          target: @target,
          declared_capabilities: ["qa", "repository_change", "supplementary_compute"],
          verified_capabilities: capabilities,
          capability_evidence_source: "bounded SSH identity/tool/workspace probe",
          capability_evidence_at: now(),
          execution_policy: "bounded_jobs_only",
          arbitrary_shell: false,
          arbitrary_systemd: false,
          production_control_plane: false,
          cpu_count: evidence.cpus,
          workspace_present: evidence.workspace,
          mix_present: evidence.mix,
          git_present: evidence.git
        }
      })
      |> ConnectorState.attach(%{
        node_id: "i7",
        hostname: evidence.hostname,
        load: nil,
        ram: nil,
        uptime_seconds: nil,
        services: []
      })
    else
      unavailable(
        "I7_NODE_EVIDENCE_INVALID",
        "Bounded i7 probe did not provide a valid hostname/CPU identity",
        latency_ms
      )
    end
  end

  def from_probe({_output, code}, latency_ms) when is_integer(code) do
    unavailable(
      "I7_NODE_UNREACHABLE",
      "Authorized i7 SSH probe failed with exit status #{code}",
      latency_ms
    )
  end

  def from_probe(_result, latency_ms) do
    unavailable("I7_NODE_EVIDENCE_INVALID", "i7 runtime evidence was invalid", latency_ms)
  end

  @doc false
  def verified_capabilities(%{cpus: cpus, mix: mix, git: git, workspace: workspace}) do
    []
    |> maybe_add("supplementary_compute", is_integer(cpus) and cpus > 0)
    |> maybe_add("repository_change", git == true and workspace == true)
    |> maybe_add("qa", mix == true and git == true and workspace == true)
  end

  defp parse_probe(output) do
    values =
      output
      |> String.split("\n", trim: true)
      |> Enum.map(&String.split(&1, "=", parts: 2))
      |> Enum.filter(&(length(&1) == 2))
      |> Map.new(fn [key, value] -> {key, String.trim(value)} end)

    %{
      hostname: values["hostname"],
      cpus: parse_integer(values["cpus"]),
      mix: values["mix"] == "1",
      git: values["git"] == "1",
      workspace: values["workspace"] == "1"
    }
  end

  defp valid_identity?(%{hostname: hostname, cpus: cpus}) do
    is_binary(hostname) and hostname != "" and is_integer(cpus) and cpus > 0
  end

  defp unavailable(error_code, error_message, latency_ms) do
    ConnectorState.build(%{
      id: "node-i7",
      name: "i7 QA & supplementary compute node",
      kind: "node",
      status: "OPTIONAL_UNAVAILABLE",
      health: "UNAVAILABLE",
      source: "bounded SSH identity/tool/workspace probe",
      source_type: "AUTHORIZED_SSH_PROBE",
      real_data: false,
      synthetic: false,
      enabled: true,
      reachable: false,
      latency_ms: latency_ms,
      error_code: error_code,
      error_message: error_message,
      metadata: %{
        role: "qa_supplementary_compute",
        target: @target,
        declared_capabilities: ["qa", "repository_change", "supplementary_compute"],
        verified_capabilities: [],
        execution_policy: "bounded_jobs_only",
        arbitrary_shell: false,
        arbitrary_systemd: false,
        production_control_plane: false
      }
    })
    |> ConnectorState.attach(%{
      node_id: "i7",
      hostname: nil,
      load: nil,
      ram: nil,
      uptime_seconds: nil,
      services: []
    })
  end

  defp maybe_add(capabilities, capability, true), do: capabilities ++ [capability]
  defp maybe_add(capabilities, _capability, false), do: capabilities
  defp parse_integer(nil), do: nil

  defp parse_integer(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp elapsed(started), do: max(System.monotonic_time(:millisecond) - started, 0)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
