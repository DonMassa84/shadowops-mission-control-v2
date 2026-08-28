defmodule ShadowOpsCore.Adapters.TccAdapter do
  @moduledoc "Read-through adapter for the existing TCC workflow registry with an exact WhatsApp execution allowlist."
  @behaviour ShadowOpsCore.Adapters.RuntimeAdapter

  alias ShadowOpsCore.Evidence

  @default_path "/home/schattenmacher/.config/shadowmaker-tasks/workflows.json"
  @agent "/home/schattenmacher/whatsapp-agent/scripts/whatsapp-agent"
  @maintenance "/home/schattenmacher/whatsapp-agent/scripts/run-maintenance.sh"
  @worker "/home/schattenmacher/whatsapp-agent/scripts/run-worker.sh"

  @execution_specs %{
    "so:wf:v1:whatsapp-status" => {@agent, ["status"], "L0", 120_000},
    "so:wf:v1:whatsapp-sync-status" => {@agent, ["sync-status"], "L0", 60_000},
    "so:wf:v1:whatsapp-worker-status" => {@agent, ["worker-status"], "L0", 60_000},
    "so:wf:v1:whatsapp-queue" => {@agent, ["queue"], "L0", 60_000},
    "so:wf:v1:whatsapp-doctor" => {@agent, ["doctor"], "L0", 120_000},
    "so:wf:v1:whatsapp-contacts" => {@agent, ["contacts"], "L0", 60_000},
    "so:wf:v1:whatsapp-report" => {@agent, ["report"], "L0", 300_000},
    "so:wf:v1:whatsapp-meta-status" => {@agent, ["meta-status"], "L0", 120_000},
    "so:wf:v1:whatsapp-maintenance-15min" => {@maintenance, ["15min"], "L0", 300_000},
    "so:wf:v1:whatsapp-maintenance-hourly" => {@maintenance, ["hourly"], "L1", 600_000},
    "so:wf:v1:whatsapp-maintenance-daily" => {@maintenance, ["daily"], "L1", 900_000},
    "so:wf:v1:whatsapp-backup" => {@agent, ["backup"], "L1", 300_000},
    "so:wf:v1:whatsapp-worker-drain" => {@worker, ["--once"], "L1", 600_000},
    "so:wf:v1:whatsapp-retry-all" => {@agent, ["retry-all"], "L1", 120_000},
    "so:wf:v1:whatsapp-purge-expired" => {@agent, ["purge-expired", "--confirm"], "L2", 300_000},
    "so:wf:v1:whatsapp-meta-subscribe" => {@agent, ["meta-subscribe", "--confirm"], "L2", 120_000}
  }

  @impl true
  def discover(opts \\ []) do
    path =
      Keyword.get(
        opts,
        :path,
        Application.get_env(:shadowops_core, :tcc_registry_path, @default_path)
      )

    with {:ok, body} <- File.read(path),
         {:ok, decoded} <- Jason.decode(body),
         workflows when is_list(workflows) <- Map.get(decoded, "workflows") do
      {:ok, Enum.map(workflows, &canonical/1)}
    else
      {:error, reason} -> {:error, {:tcc_registry_unavailable, reason}}
      _ -> {:error, :invalid_tcc_registry}
    end
  end

  @impl true
  def status(opts \\ []) do
    case discover(opts) do
      {:ok, workflows} ->
        %{
          state: "CONNECTED",
          discovered: length(workflows),
          executable_allowlist: map_size(@execution_specs),
          source: "tcc",
          discovery: "PASS",
          arbitrary_shell: "BLOCKED"
        }

      {:error, reason} ->
        %{state: "UNAVAILABLE", discovered: 0, source: "tcc", reason: inspect(reason)}
    end
  end

  @impl true
  def validate(%{id: id, risk_level: risk}) when is_binary(id) and risk in ~w(L0 L1 L2 L3),
    do: :ok

  def validate(_), do: {:error, :invalid_tcc_workflow}

  @impl true
  def run(%{id: id}, _inputs, _context) when is_binary(id) do
    case Map.get(@execution_specs, id) do
      nil ->
        {:error, :workflow_not_allowlisted}

      {_executable, _args, risk, _timeout} when risk in ["L2", "L3"] ->
        {:error, :approval_required}

      {executable, args, risk, timeout} ->
        execute(id, executable, args, risk, timeout)
    end
  end

  def run(_, _, _), do: {:error, :invalid_tcc_workflow}

  defp execute(id, executable, args, risk, timeout) do
    task =
      Task.async(fn ->
        System.cmd(executable, args, stderr_to_stdout: true)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, 0}} ->
        {:ok,
         %{
           workflow_id: id,
           status: "SUCCESS",
           risk: risk,
           executable: executable,
           args: args,
           exit_code: 0,
           output: output,
           arbitrary_shell: false
         }}

      {:ok, {output, exit_code}} ->
        {:error, {:execution_failed, exit_code, output}}

      nil ->
        {:error, :execution_timeout}
    end
  end

  @impl true
  def stop(_, _), do: {:error, :stop_not_supported}

  @impl true
  def health(workflow), do: %{status: if(validate(workflow) == :ok, do: "PASS", else: "FAIL")}

  @impl true
  def evidence(%{id: id} = workflow) do
    Evidence.build(
      "workflow:" <> id,
      "tcc_registry",
      [
        %{
          gate: "manifest",
          result: if(validate(workflow) == :ok, do: "PASS", else: "FAIL"),
          evidence_ref: "tcc:" <> id
        }
      ],
      "local TCC registry"
    )
  end

  defp canonical(workflow) do
    raw_id = workflow["id"] || workflow["name"]

    id =
      if String.starts_with?(raw_id || "", "so:wf:v1:"),
        do: raw_id,
        else: "so:wf:v1:" <> to_string(raw_id)

    spec = Map.get(@execution_specs, id)
    risk = workflow["risk_level"] || workflow["risk"] || workflow["approval_level"]

    %{
      id: id,
      name: workflow["name"] || workflow["id"],
      source: "tcc",
      runtime: "tcc",
      executor: if(spec, do: elem(spec, 0), else: nil),
      target: List.first(workflow["allowed_targets"] || []),
      risk_level: risk,
      approval_required: risk in ~w(L2 L3),
      inputs: workflow["inputs"] || [],
      outputs: workflow["outputs"] || [],
      connectors: workflow["connectors"] || %{},
      privacy: workflow["privacy"] || "local_only",
      evidence_required: true,
      synthetic: false
    }
  end
end
