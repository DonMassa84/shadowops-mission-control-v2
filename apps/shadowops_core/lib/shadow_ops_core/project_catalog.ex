defmodule ShadowOpsCore.ProjectCatalog do
  @moduledoc """
  Canonical reader and normalizer for the local federated project catalog.

  Only bounded metadata is projected. Raw project content, local export paths,
  credentials, and arbitrary source fields are discarded during normalization.
  """

  alias ShadowOpsCore.Truthfulness

  @default_relative [".local", "state", "shadowops", "project_catalog.json"]
  @domains ~w(shadowops ihk social ai knowledge career ops evidence backup reporting other)

  @spec default_path() :: String.t()
  def default_path, do: Path.join([System.user_home!() | @default_relative])

  @spec snapshot(String.t()) :: map()
  def snapshot(path \\ default_path()) when is_binary(path) do
    case File.read(path) do
      {:ok, body} -> decode(path, body)
      {:error, :enoent} -> unavailable(path, "SOURCE_MISSING", "Project catalog is not generated")
      {:error, reason} -> unavailable(path, "SOURCE_UNREADABLE", inspect(reason))
    end
  end

  @doc """
  Replaces one provider's bounded project records while preserving every other provider.

  The resulting list is deterministic and de-duplicated by `{source_type, id}`.
  """
  @spec merge_provider_projects([map()], [map()], String.t()) :: [map()]
  def merge_provider_projects(existing, provider_projects, source_type)
      when is_list(existing) and is_list(provider_projects) and is_binary(source_type) do
    preserved = Enum.reject(existing, &(value(&1, :source_type) == source_type))

    (preserved ++ provider_projects)
    |> Enum.map(&normalize_maybe/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.source_type, &1.id})
    |> Enum.sort_by(&{&1.source_type, &1.id})
  end

  @doc """
  Correlates one existing catalog record with bounded source-truth metadata.

  The project identity and provider metadata are preserved. Private local
  paths and arbitrary manifest fields are never projected into the catalog.
  """
  @spec correlate_project(map(), String.t(), map()) :: map()
  def correlate_project(%{projects: projects} = catalog, project_id, source_truth)
      when is_list(projects) and is_binary(project_id) and is_map(source_truth) do
    if catalog.status in ["NOT_CONFIGURED", "UNAVAILABLE"] do
      catalog
    else
      projects =
        Enum.map(projects, fn
          %{id: ^project_id} = project ->
            correlate_project_record(project, source_truth)

          project ->
            project
        end)

      %{catalog | projects: projects, counts: counts(projects)}
    end
  end

  def correlate_project(catalog, _project_id, _source_truth), do: catalog

  @spec normalize_project(map()) :: map() | nil
  def normalize_project(project) when is_map(project) do
    id = string_value(project, "id")
    name = string_value(project, "name")

    if is_nil(id) or is_nil(name) do
      nil
    else
      candidate = %{
        status: string_value(project, "status") || "NOT_CONFIGURED",
        real_data: boolean_value(project, "real_data"),
        synthetic: boolean_value(project, "synthetic"),
        reachable: boolean_value(project, "reachable")
      }

      status =
        if candidate.status == "READY",
          do: Truthfulness.normalize_ready_state(candidate),
          else: candidate.status

      %{
        id: id,
        name: name,
        domain: safe_domain(string_value(project, "domain")),
        source_type: string_value(project, "source_type") || "UNKNOWN",
        status: status,
        visibility: string_value(project, "visibility"),
        default_branch: string_value(project, "default_branch"),
        archived: boolean_value(project, "archived"),
        real_data: candidate.real_data,
        synthetic: candidate.synthetic,
        reachable: candidate.reachable,
        content_ingested: boolean_value(project, "content_ingested"),
        integration_mode: string_value(project, "integration_mode") || "REFERENCE_ONLY",
        url: safe_github_url(string_value(project, "url"))
      }
    end
  end

  def normalize_project(_), do: nil

  defp correlate_project_record(project, source_truth) do
    candidate = %{
      status: catalog_status(project_truth_value(source_truth, :status)),
      real_data: project_truth_value(source_truth, :real_data) == true,
      synthetic: project_truth_value(source_truth, :synthetic) == true,
      reachable: project_truth_value(source_truth, :reachable) == true
    }

    status =
      if candidate.status == "READY",
        do: Truthfulness.normalize_ready_state(candidate),
        else: candidate.status

    project
    |> Map.put(:status, status)
    |> Map.put(:real_data, candidate.real_data)
    |> Map.put(:synthetic, candidate.synthetic)
    |> Map.put(:reachable, candidate.reachable)
    |> Map.put(:integration_mode, "LOCAL_MANIFEST_CORRELATED")
  end

  defp catalog_status(status)
       when status in [
              "READY",
              "DISCOVERED",
              "DEGRADED",
              "BLOCKED",
              "UNAVAILABLE",
              "NOT_CONFIGURED"
            ],
       do: status

  # Domain-specific lifecycle values such as ACTIVE prove presence, but not
  # catalog readiness. They therefore collapse safely to DISCOVERED.
  defp catalog_status(_status), do: "DISCOVERED"

  defp project_truth_value(map, key),
    do: Map.get(map, key, Map.get(map, to_string(key)))

  defp decode(path, body) do
    case Jason.decode(body) do
      {:ok, %{"projects" => projects} = data} when is_list(projects) ->
        normalized = projects |> Enum.map(&normalize_project/1) |> Enum.reject(&is_nil/1)

        %{
          status: "READY",
          health: "HEALTHY",
          source_type: "LOCAL_FEDERATED_PROJECT_CATALOG",
          source: path,
          generated_at: Map.get(data, "generated_at"),
          schema_version: Map.get(data, "schema_version"),
          github_discovery_mode: Map.get(data, "github_discovery_mode", "UNKNOWN"),
          synthetic: false,
          real_data: true,
          reachable: true,
          counts: counts(normalized),
          projects: normalized,
          error_code: nil,
          error_message: nil
        }

      {:ok, _other} ->
        unavailable(path, "INVALID_SCHEMA", "Catalog root must contain a projects array")

      {:error, reason} ->
        unavailable(path, "INVALID_JSON", Exception.message(reason))
    end
  end

  defp counts(projects) do
    %{
      total: length(projects),
      github: Enum.count(projects, &(&1.source_type == "github_repository")),
      chatgpt: Enum.count(projects, &(&1.source_type == "chatgpt_library_project")),
      ready: Enum.count(projects, &(&1.status == "READY")),
      discovered: Enum.count(projects, &(&1.status == "DISCOVERED")),
      not_configured: Enum.count(projects, &(&1.status == "NOT_CONFIGURED")),
      degraded: Enum.count(projects, &(&1.status == "DEGRADED")),
      blocked: Enum.count(projects, &(&1.status == "BLOCKED")),
      unavailable: Enum.count(projects, &(&1.status == "UNAVAILABLE"))
    }
  end

  defp unavailable(path, code, message) do
    %{
      status: "NOT_CONFIGURED",
      health: "UNAVAILABLE",
      source_type: "LOCAL_FEDERATED_PROJECT_CATALOG",
      source: path,
      generated_at: nil,
      schema_version: nil,
      github_discovery_mode: "UNAVAILABLE",
      synthetic: false,
      real_data: false,
      reachable: false,
      counts: %{
        total: nil,
        github: nil,
        chatgpt: nil,
        ready: nil,
        discovered: nil,
        not_configured: nil,
        degraded: nil,
        blocked: nil,
        unavailable: nil
      },
      projects: [],
      error_code: code,
      error_message: message
    }
  end

  defp normalize_maybe(%{} = project) do
    normalized = normalize_project(project)

    if is_nil(normalized) do
      project
      |> stringify_keys()
      |> normalize_project()
    else
      normalized
    end
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, to_string(key)))

  defp string_value(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp boolean_value(map, key), do: Map.get(map, key) == true

  defp safe_domain(domain) when domain in @domains, do: domain
  defp safe_domain(nil), do: nil
  defp safe_domain(_), do: "other"

  defp safe_github_url("https://github.com/" <> _rest = url), do: url
  defp safe_github_url(_), do: nil
end
