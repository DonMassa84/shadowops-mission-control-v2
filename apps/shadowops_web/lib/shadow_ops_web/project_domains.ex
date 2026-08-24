defmodule ShadowOpsWeb.ProjectDomains do
  @moduledoc """
  Read-only, fail-visible project-domain registry.

  Domain manifests stay local and are never committed by this module. Each source is a JSON object
  with optional `status`, `health`, `summary`, `open_items`, `next_deadline`, `updated_at`, and
  `classification` fields. Missing or invalid sources remain explicit.
  """

  @domains %{
    shadowops: {"ShadowOps", "SHADOWOPS_SHADOWOPS_MANIFEST", "shadowops.json"},
    infrastructure:
      {"Infrastructure", "SHADOWOPS_INFRASTRUCTURE_MANIFEST", "infrastructure.json"},
    career: {"Career", "SHADOWOPS_CAREER_MANIFEST", "career.json"},
    finance: {"Finance", "SHADOWOPS_FINANCE_MANIFEST", "finance.json"},
    investigations:
      {"Investigations", "SHADOWOPS_INVESTIGATIONS_MANIFEST", "investigations.json"},
    legal: {"Legal", "SHADOWOPS_LEGAL_MANIFEST", "legal.json"},
    ihk: {"IHK / Zero Trust", "SHADOWOPS_IHK_MANIFEST", "ihk.json"},
    community: {"Community", "SHADOWOPS_COMMUNITY_MANIFEST", "community.json"},
    social: {"Social", "SHADOWOPS_SOCIAL_MANIFEST", "social.json"},
    knowledge: {"Knowledge", "SHADOWOPS_KNOWLEDGE_MANIFEST", "knowledge.json"},
    housing: {"Housing", "SHADOWOPS_HOUSING_MANIFEST", "housing.json"},
    administration:
      {"Administration", "SHADOWOPS_ADMINISTRATION_MANIFEST", "administration.json"},
    health: {"Health", "SHADOWOPS_HEALTH_MANIFEST", "health.json"},
    learning: {"Learning", "SHADOWOPS_LEARNING_MANIFEST", "learning.json"},
    personal_framework:
      {"Personal Framework", "SHADOWOPS_PERSONAL_FRAMEWORK_MANIFEST", "personal_framework.json"}
  }

  def all do
    @domains
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map(&snapshot/1)
  end

  def snapshot(id) when is_atom(id) do
    case Map.fetch(@domains, id) do
      {:ok, {name, env_name, file_name}} -> load(id, name, env_name, file_name)
      :error -> unavailable(id, to_string(id), nil, "UNKNOWN_DOMAIN", "Unknown project domain")
    end
  end

  def snapshot(id) when is_binary(id) do
    case Enum.find(Map.keys(@domains), &(Atom.to_string(&1) == id)) do
      nil -> unavailable(id, id, nil, "UNKNOWN_DOMAIN", "Unknown project domain")
      domain -> snapshot(domain)
    end
  end

  defp load(id, name, env_name, file_name) do
    path = System.get_env(env_name) || Path.join(default_root(), file_name)

    case File.read(path) do
      {:ok, body} ->
        decode(id, name, path, body)

      {:error, :enoent} ->
        unavailable(id, name, path, "SOURCE_MISSING", "No local manifest is configured")

      {:error, reason} ->
        unavailable(id, name, path, "SOURCE_UNREADABLE", inspect(reason))
    end
  end

  defp decode(id, name, path, body) do
    case Jason.decode(body) do
      {:ok, data} when is_map(data) ->
        %{
          id: to_string(id),
          name: name,
          status: value(data, "status", "READY"),
          health: value(data, "health", "HEALTHY"),
          summary: value(data, "summary", "Local manifest connected"),
          open_items: integer_value(data, "open_items"),
          next_deadline: value(data, "next_deadline", nil),
          updated_at: value(data, "updated_at", file_mtime(path)),
          classification: value(data, "classification", "PRIVATE_LOCAL"),
          source: path,
          source_type: "LOCAL_JSON_MANIFEST",
          real_data: true,
          synthetic: false,
          reachable: true,
          error_code: nil,
          error_message: nil
        }

      {:ok, _other} ->
        unavailable(id, name, path, "INVALID_SCHEMA", "Manifest root must be a JSON object")

      {:error, reason} ->
        unavailable(id, name, path, "INVALID_JSON", Exception.message(reason))
    end
  end

  defp unavailable(id, name, source, code, message) do
    %{
      id: to_string(id),
      name: name,
      status: "NOT_CONFIGURED",
      health: "UNAVAILABLE",
      summary: message,
      open_items: nil,
      next_deadline: nil,
      updated_at: nil,
      classification: "PRIVATE_LOCAL",
      source: source,
      source_type: "LOCAL_JSON_MANIFEST",
      real_data: false,
      synthetic: false,
      reachable: false,
      error_code: code,
      error_message: message
    }
  end

  defp value(data, key, default), do: Map.get(data, key, default)

  defp integer_value(data, key) do
    case Map.get(data, key) do
      value when is_integer(value) and value >= 0 -> value
      _ -> nil
    end
  end

  defp default_root do
    System.get_env("SHADOWOPS_DOMAIN_DIR") ||
      Path.join([System.user_home!(), ".local", "share", "shadowops", "domains"])
  end

  defp file_mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, stat} -> DateTime.from_unix!(stat.mtime) |> DateTime.to_iso8601()
      _ -> nil
    end
  end
end
