defmodule ShadowOpsCore.Adapters.SystemctlServiceRuntime do
  @moduledoc """
  Systemd service runtime adapter using systemctl CLI.

  Discovers user and system services, proves exact runtime identity
  via scope:name, LoadState, FragmentPath, and source verification.
  """
  @behaviour ShadowOpsCore.Adapters.ServiceRuntimeAdapter

  @impl true
  def services do
    user_rows =
      list_services("user", [
        "--user",
        "--no-legend",
        "--plain",
        "list-units",
        "--type=service",
        "--all"
      ])

    system_rows =
      list_services("system", ["--no-legend", "--plain", "list-units", "--type=service", "--all"])

    all = user_rows ++ system_rows
    all = enrich_fragment_paths(all)
    {:ok, all}
  rescue
    _ -> {:ok, []}
  end

  @impl true
  def service(identity, services \\ nil) when is_binary(identity) do
    with {:ok, services} <- ensure_services(services),
         %{} = found <- Enum.find(services, &(&1.identity == identity)) do
      {:ok, found}
    else
      _ -> {:error, :not_found}
    end
  end

  @impl true
  def runtime_identity(identity, services \\ nil) when is_binary(identity) do
    with {:ok, svc} <- service(identity, services) do
      verified = verify_runtime_identity(svc)
      {:ok, verified}
    end
  end

  defp ensure_services(nil), do: services()
  defp ensure_services(services) when is_list(services), do: {:ok, services}

  defp list_services(scope, args) do
    case System.cmd("systemctl", args, stderr_to_stdout: true) do
      {body, 0} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn line ->
          case String.split(line, ~r/\s+/, parts: 5) do
            [name, load, active, sub, description] ->
              identity = "#{scope}:#{name}"

              [
                %{
                  scope: scope,
                  name: name,
                  identity: identity,
                  load_state: load,
                  active_state: active,
                  sub_state: sub,
                  description: description,
                  fragment_path: nil,
                  source_path: nil,
                  pid: nil,
                  restart_count: nil,
                  last_error: nil,
                  status: "DISCOVERED",
                  reachable: active in ["active", "activating", "reloading"],
                  real_data: false,
                  synthetic: false,
                  runtime_verified: false,
                  connected: false,
                  live: active in ["active"],
                  source: "systemctl",
                  updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
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

  defp enrich_fragment_paths([]), do: []

  defp enrich_fragment_paths(rows) do
    by_identity = Enum.map(rows, fn row -> {row.identity, row} end)

    paths = fetch_paths_batch(rows)

    Enum.map(by_identity, fn {identity, row} ->
      case Map.get(paths, identity) do
        {fragment_path, source_path} ->
          %{
            row
            | fragment_path: fragment_path,
              source_path: source_path,
              runtime_verified: fragment_path != nil
          }

        nil ->
          row
      end
    end)
  end

  defp fetch_paths_batch(rows) do
    by_scope = Enum.group_by(rows, & &1.scope)

    Enum.flat_map(by_scope, fn {scope, scoped_rows} ->
      names = Enum.map(scoped_rows, & &1.name)
      args = if scope == "user", do: ["--user", "show"], else: ["show"]

      args = args ++ ["--property=FragmentPath", "--property=SourcePath", "--"] ++ names

      case System.cmd("systemctl", args, stderr_to_stdout: true) do
        {body, 0} ->
          parse_paths_block(body, scope)

        _ ->
          []
      end
    end)
    |> Map.new()
  rescue
    _ -> %{}
  end

  defp parse_paths_block(body, scope) do
    body
    |> String.split(~r/\n\s*\n/, trim: true)
    |> Enum.map(fn block ->
      values =
        block
        |> String.split("\n", trim: true)
        |> Enum.map(&String.split(&1, "=", parts: 2))
        |> Enum.filter(&(length(&1) == 2))
        |> Map.new(fn [k, v] -> {k, v} end)

      name = values["Id"] || values["FragmentPath"] || values["SourcePath"]
      fragment = fragment_or_nil(values["FragmentPath"])
      source = fragment_or_nil(values["SourcePath"])
      identity = "#{scope}:#{name}"
      {identity, {fragment, source}}
    end)
  end

  defp fragment_or_nil(nil), do: nil
  defp fragment_or_nil(""), do: nil
  defp fragment_or_nil(value) when is_binary(value), do: value

  defp verify_runtime_identity(svc) do
    fragment_path = svc.fragment_path || get_fragment_path(svc.scope, svc.name)
    source_path = svc.source_path || get_source_path(svc.scope, svc.name)

    verified = %{
      svc
      | fragment_path: fragment_path,
        source_path: source_path,
        runtime_verified: fragment_path != nil
    }

    if fragment_path do
      %{verified | status: "RUNTIME_VERIFIED"}
    else
      %{verified | status: "DISCOVERED", runtime_verified: false}
    end
  end

  defp get_fragment_path(scope, name) do
    args = if scope == "user", do: ["--user", "show", name], else: ["show", name]

    case System.cmd("systemctl", args ++ ["--property=FragmentPath"], stderr_to_stdout: true) do
      {body, 0} ->
        body
        |> String.trim()
        |> String.replace_leading("FragmentPath=", "")
        |> case do
          "" -> nil
          path -> path
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp get_source_path(scope, name) do
    args = if scope == "user", do: ["--user", "show", name], else: ["show", name]

    case System.cmd("systemctl", args ++ ["--property=SourcePath"], stderr_to_stdout: true) do
      {body, 0} ->
        body
        |> String.trim()
        |> String.replace_leading("SourcePath=", "")
        |> case do
          "" -> nil
          path -> path
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end
end
