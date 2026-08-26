defmodule ShadowOpsCore.RuntimeSources do
  @moduledoc "Read-only adapters for actual local runtime and metadata sources."
  alias ShadowOpsCore.{ConnectorState, OperationalSources}

  @service_action_allowlist ["user:shadowops-phoenix.service"]
  def services do
    systemd_rows =
      Enum.flat_map(
        [
          {"user", ["--user", "--no-legend", "--plain", "list-units", "--type=service", "--all"]},
          {"system", ["--no-legend", "--plain", "list-units", "--type=service", "--all"]}
        ],
        &service_scope/1
      )
      |> enrich_systemd()

    docker_rows = docker_services()
    rows = systemd_rows ++ docker_rows

    sources =
      ["systemctl --user", "systemctl"] ++
        if(docker_rows == [], do: [], else: ["docker ps"])

    status = if(rows == [], do: "UNAVAILABLE", else: "READY")

    ConnectorState.build(%{
      id: "services",
      name: "Services",
      kind: "services",
      status: status,
      health: if(rows == [], do: "UNAVAILABLE", else: "HEALTHY"),
      source: Enum.join(sources, " / "),
      source_type: "LOCAL_RUNTIME",
      real_data: rows != [],
      synthetic: false,
      enabled: true,
      reachable: rows != [],
      last_success_at: if(rows == [], do: nil, else: now()),
      record_count: length(rows),
      metadata: %{action_allowlist: @service_action_allowlist}
    })
    |> ConnectorState.attach(%{
      availability: if(rows == [], do: "UNAVAILABLE", else: "AVAILABLE"),
      updated_at: now(),
      services: rows
    })
  end

  def system, do: OperationalSources.system()
  def nodes, do: OperationalSources.nodes()
  def node(id), do: OperationalSources.node(id)
  def node_action(id, action), do: OperationalSources.node_action(id, action)
  def agents, do: OperationalSources.agents(services())
  def ai, do: OperationalSources.ai()
  def whatsapp, do: OperationalSources.whatsapp()
  def social, do: OperationalSources.social(services())
  def career, do: OperationalSources.career()
  def backups, do: OperationalSources.backups()
  def logs(filters \\ %{}), do: OperationalSources.logs(filters)
  def reporting(modules), do: OperationalSources.reporting(modules)

  def service(id) do
    case Enum.find(services().services, &(service_id(&1) == id or &1.name == id)) do
      nil -> {:error, :not_found}
      service -> {:ok, Map.put(service, :id, service_id(service))}
    end
  end

  def service_action(id, "status"), do: service(id)

  def service_action(id, action) when action in ["start", "stop", "restart"] do
    with true <- id in @service_action_allowlist,
         [scope, name] <- String.split(id, ":", parts: 2),
         args = if(scope == "user", do: ["--user", action, name], else: [action, name]),
         {_output, 0} <- System.cmd("systemctl", args, stderr_to_stdout: true) do
      service(id)
    else
      false -> {:error, :service_not_allowlisted}
      {_output, code} -> {:error, {:systemctl_failed, code}}
      _ -> {:error, :invalid_service_id}
    end
  rescue
    error -> {:error, {:service_action_failed, Exception.message(error)}}
  end

  def service_action(_id, _action), do: {:error, :action_not_allowed}

  @doc false
  def knowledge_sources do
    Enum.map(
      [
        "/home/schattenmacher/ProofFlow-Obsidian-Vault",
        "/home/schattenmacher/shadowops-knowledge",
        "/home/schattenmacher/workflow-knowledge"
      ],
      &metadata/1
    )
  end

  def knowledge do
    sources = knowledge_sources()

    OperationalSources.knowledge(sources)
    |> Map.put(:availability, aggregate_availability(sources))
    |> Map.put(:updated_at, now())
  end

  def evidence do
    path = Path.expand("../../../../docs/evidence", __DIR__)
    evidence_snapshot(path)
  end

  @doc false
  def evidence_snapshot(path) when is_binary(path) do
    sources = [metadata(path)]
    artifacts = evidence_artifacts(path)

    availability = aggregate_availability(sources)
    reachable = availability == "AVAILABLE"
    has_artifacts = artifacts != []

    {status, health, real_data, error_code, error_message} =
      cond do
        reachable and has_artifacts ->
          {"READY", "HEALTHY", true, nil, nil}

        reachable ->
          {"DEGRADED", "DEGRADED", false, "EVIDENCE_EMPTY",
           "Evidence source is available but contains no artifacts"}

        true ->
          {"UNAVAILABLE", "UNAVAILABLE", false, "SOURCE_MISSING",
           "Project evidence directory is unavailable"}
      end

    ConnectorState.build(%{
      id: "evidence",
      name: "Evidence",
      kind: "evidence",
      status: status,
      health: health,
      source: "project evidence directory",
      source_type: "LOCAL_FILESYSTEM",
      real_data: real_data,
      synthetic: false,
      enabled: true,
      reachable: reachable,
      last_success_at: if(reachable, do: now(), else: nil),
      record_count: if(reachable, do: length(artifacts), else: nil),
      error_code: error_code,
      error_message: error_message,
      metadata: %{
        verification_semantics: "AVAILABLE_ONLY",
        verified_claims_implied: false
      }
    })
    |> ConnectorState.attach(%{
      availability: availability,
      updated_at: now(),
      sources: sources,
      artifacts: artifacts
    })
  end

  defp service_scope({scope, args}) do
    case System.cmd("systemctl", args, stderr_to_stdout: true) do
      {body, 0} ->
        Enum.flat_map(String.split(body, "\n", trim: true), fn line ->
          case String.split(line, ~r/\s+/, parts: 5) do
            [name, _load, active, sub, description] ->
              [
                %{
                  name: name,
                  scope: scope,
                  active_state: active,
                  sub_state: sub,
                  description: description,
                  source: "systemctl",
                  enabled: nil,
                  pid: nil,
                  uptime_seconds: nil,
                  last_error: nil,
                  restart_count: nil,
                  updated_at: now()
                }
              ]

            _ ->
              []
          end
        end)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp enrich_systemd(rows) do
    rows
    |> Enum.group_by(& &1.scope)
    |> Enum.flat_map(fn {scope, scoped_rows} ->
      details = service_details(scope, Enum.map(scoped_rows, & &1.name))

      Enum.map(scoped_rows, fn row ->
        row =
          case details[row.name] do
            nil -> row
            detail -> Map.merge(row, detail)
          end

        row =
          Map.merge(row, service_contract(row.active_state, row.sub_state, row.last_error))

        Map.merge(row, %{
          fragment_path: Map.get(row, :fragment_path, nil),
          source_path: Map.get(row, :source_path, nil),
          runtime_verified: not is_nil(Map.get(row, :fragment_path, nil))
        })
      end)
    end)
  end

  defp service_details(_scope, []), do: %{}

  defp service_details(scope, names) do
    properties =
      "Id,ActiveState,SubState,UnitFileState,MainPID,NRestarts,Result,ExecMainStatus,ActiveEnterTimestampMonotonic,FragmentPath,SourcePath"

    args =
      if scope == "user",
        do: ["--user", "show", "--property=" <> properties, "--"] ++ names,
        else: ["show", "--property=" <> properties, "--"] ++ names

    case System.cmd("systemctl", args, stderr_to_stdout: true) do
      {body, 0} ->
        body
        |> String.split(~r/\n\s*\n/, trim: true)
        |> Enum.map(&parse_service_detail/1)
        |> Enum.reject(&is_nil/1)
        |> Map.new(fn detail -> {detail.id, Map.delete(detail, :id)} end)

      _ ->
        %{}
    end
  rescue
    _ -> %{}
  end

  defp parse_service_detail(block) do
    values =
      block
      |> String.split("\n", trim: true)
      |> Enum.map(&String.split(&1, "=", parts: 2))
      |> Enum.filter(&(length(&1) == 2))
      |> Map.new(fn [key, value] -> {key, value} end)

    if values["Id"] do
      %{
        id: values["Id"],
        active_state: values["ActiveState"],
        sub_state: values["SubState"],
        enabled: values["UnitFileState"],
        pid: integer(values["MainPID"]),
        uptime_seconds: service_uptime(values["ActiveEnterTimestampMonotonic"]),
        restart_count: integer(values["NRestarts"]),
        last_error: service_error(values["Result"], values["ExecMainStatus"]),
        fragment_path: fragment_or_nil(values["FragmentPath"]),
        source_path: fragment_or_nil(values["SourcePath"])
      }
    end
  end

  defp fragment_or_nil(nil), do: nil
  defp fragment_or_nil(""), do: nil
  defp fragment_or_nil(value) when is_binary(value), do: value

  defp service_uptime(value) do
    with entered when is_integer(entered) and entered > 0 <- integer(value),
         {:ok, body} <- File.read("/proc/uptime"),
         {boot_seconds, _} <- Float.parse(body) do
      max(trunc(boot_seconds - entered / 1_000_000), 0)
    else
      _ -> nil
    end
  end

  defp service_error(result, status) do
    case {result, integer(status)} do
      {result, code} when result in [nil, "", "success"] and code in [nil, 0] -> nil
      {result, code} -> %{result: result, exit_status: code}
    end
  end

  defp integer(nil), do: nil

  defp integer(value) do
    case Integer.parse(value) do
      {number, _} -> number
      _ -> nil
    end
  end

  defp docker_services do
    case System.cmd("docker", ["ps", "--all", "--format", "{{json .}}"], stderr_to_stdout: true) do
      {body, 0} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn line ->
          case parse_docker_line(line, now()) do
            {:ok, record} -> [record]
            :error -> []
          end
        end)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  @doc false
  def parse_docker_line(line, updated_at) when is_binary(line) and is_binary(updated_at) do
    with {:ok, row} <- Jason.decode(line),
         name when is_binary(name) and name != "" <- row["Names"],
         state when is_binary(state) and state != "" <- row["State"],
         status when is_binary(status) and status != "" <- row["Status"] do
      {:ok,
       Map.merge(
         %{
           name: name,
           scope: "container",
           active_state: state,
           sub_state: status,
           description: row["Image"] || "Docker container",
           source: "docker",
           enabled: nil,
           pid: nil,
           uptime_seconds: nil,
           last_error: nil,
           restart_count: nil,
           updated_at: updated_at
         },
         service_contract(state, status, nil)
       )}
    else
      _ -> :error
    end
  end

  defp metadata(path) do
    case File.stat(path) do
      {:ok, stat} ->
        %{
          source: Path.basename(path),
          availability: "AVAILABLE",
          document_count:
            if(File.dir?(path),
              do: Path.wildcard(Path.join(path, "**/*")) |> Enum.count(&File.regular?/1),
              else: 1
            ),
          last_update: stat.mtime |> NaiveDateTime.from_erl!() |> NaiveDateTime.to_iso8601()
        }

      _ ->
        %{source: Path.basename(path), availability: "UNAVAILABLE"}
    end
  end

  defp aggregate_availability(sources),
    do:
      if(Enum.any?(sources, &(&1.availability == "AVAILABLE")),
        do: "AVAILABLE",
        else: "UNAVAILABLE"
      )

  defp service_contract(active, _sub, error) do
    status =
      cond do
        active in ["active", "running"] and is_nil(error) ->
          "READY"

        active in ["failed", "activating", "deactivating", "reloading"] or not is_nil(error) ->
          "DEGRADED"

        active in ["inactive", "dead", "exited", "created"] ->
          "UNAVAILABLE"

        true ->
          "UNKNOWN"
      end

    %{
      status: status,
      health:
        case status do
          "READY" -> "HEALTHY"
          "DEGRADED" -> "DEGRADED"
          "UNAVAILABLE" -> "UNAVAILABLE"
          _ -> "UNKNOWN"
        end,
      real_data: true,
      synthetic: false,
      reachable: status == "READY",
      optional: active in ["inactive", "dead", "exited", "created"],
      canonical_source: "runtime process state"
    }
  end

  defp service_id(service), do: service.scope <> ":" <> service.name

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp evidence_artifacts(path) do
    if File.dir?(path) do
      path
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(fn file ->
        {:ok, stat} = File.stat(file)

        %{
          artifact: Path.basename(file),
          type: file |> Path.extname() |> String.trim_leading(".") |> String.upcase(),
          modified: stat.mtime |> NaiveDateTime.from_erl!() |> NaiveDateTime.to_iso8601(),
          source_category: "project evidence",
          verification_status: "AVAILABLE"
        }
      end)
      |> Enum.sort_by(& &1.artifact)
    else
      []
    end
  end
end
