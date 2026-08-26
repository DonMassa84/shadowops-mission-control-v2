defmodule ShadowOpsCore.ChatGPTSource do
  @moduledoc """
  Fail-closed reader for a local ChatGPT export.

  The module deliberately projects bounded project metadata only. Raw conversation
  bodies, attachments, credentials, and local source paths are never returned in
  normalized project records.
  """

  alias ShadowOpsCore.ProjectCatalog

  @source_type "chatgpt_library_project"

  @spec snapshot(String.t() | nil) :: map()
  def snapshot(path \\ System.get_env("SHADOWOPS_CHATGPT_EXPORT_DIR"))

  def snapshot(nil),
    do: unavailable("SOURCE_MISSING", "SHADOWOPS_CHATGPT_EXPORT_DIR is not configured")

  def snapshot(path) when is_binary(path) do
    cond do
      not File.dir?(path) ->
        unavailable("SOURCE_MISSING", "Configured ChatGPT export directory is not reachable")

      true ->
        discover(path)
    end
  end

  @spec project_records(String.t() | nil) :: [map()]
  def project_records(path \\ System.get_env("SHADOWOPS_CHATGPT_EXPORT_DIR")) do
    case snapshot(path) do
      %{status: "READY", projects: projects} -> projects
      _ -> []
    end
  end

  defp discover(path) do
    candidates = [
      Path.join(path, "projects.json"),
      Path.join(path, "project.json"),
      Path.join(path, "conversations.json")
    ]

    case Enum.find(candidates, &File.regular?/1) do
      nil -> unavailable("SOURCE_MISSING", "No supported ChatGPT export metadata file was found")
      file -> decode(file)
    end
  end

  defp decode(file) do
    with {:ok, body} <- File.read(file),
         {:ok, decoded} <- Jason.decode(body),
         projects when is_list(projects) <- extract_projects(decoded),
         normalized when is_list(normalized) <- normalize(projects),
         true <- normalized != [] do
      %{
        status: "READY",
        health: "HEALTHY",
        source_type: "LOCAL_CHATGPT_EXPORT",
        real_data: true,
        synthetic: false,
        reachable: true,
        projects: normalized,
        count: length(normalized),
        error_code: nil,
        error_message: nil
      }
    else
      {:error, %Jason.DecodeError{} = reason} ->
        unavailable("INVALID_JSON", Exception.message(reason))

      {:error, reason} ->
        unavailable("SOURCE_UNREADABLE", inspect(reason))

      false ->
        unavailable("NO_PROJECT_EVIDENCE", "No valid ChatGPT project metadata was evidenced")

      _ ->
        unavailable("INVALID_SCHEMA", "Unsupported ChatGPT export schema")
    end
  end

  defp extract_projects(%{"projects" => projects}) when is_list(projects), do: projects

  defp extract_projects(conversations) when is_list(conversations) do
    conversations
    |> Enum.map(&conversation_project/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&Map.get(&1, "id"))
  end

  defp extract_projects(_), do: :invalid

  defp conversation_project(%{} = conversation) do
    project_id =
      value(conversation, ["project_id", "projectId"]) ||
        nested_value(conversation, ["project", "id"])

    project_name =
      value(conversation, ["project_name", "projectName"]) ||
        nested_value(conversation, ["project", "name"])

    if is_binary(project_id) and project_id != "" and is_binary(project_name) and project_name != "" do
      %{"id" => project_id, "name" => project_name}
    end
  end

  defp conversation_project(_), do: nil

  defp normalize(projects) do
    projects
    |> Enum.map(fn project ->
      project
      |> bounded_project()
      |> ProjectCatalog.normalize_project()
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp bounded_project(%{} = project) do
    %{
      "id" => value(project, ["id", "project_id", "projectId"]),
      "name" => value(project, ["name", "title", "project_name", "projectName"]),
      "source_type" => @source_type,
      "status" => "READY",
      "visibility" => "PRIVATE_LOCAL",
      "real_data" => true,
      "synthetic" => false,
      "reachable" => true,
      "content_ingested" => false,
      "integration_mode" => "REFERENCE_ONLY"
    }
  end

  defp bounded_project(_), do: %{}

  defp value(map, keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(map, key) do
        value when is_binary(value) and value != "" -> value
        _ -> nil
      end
    end)
  end

  defp nested_value(map, [outer, inner]) do
    case Map.get(map, outer) do
      %{} = nested -> value(nested, [inner])
      _ -> nil
    end
  end

  defp unavailable(code, message) do
    %{
      status: "NOT_CONFIGURED",
      health: "UNAVAILABLE",
      source_type: "LOCAL_CHATGPT_EXPORT",
      real_data: false,
      synthetic: false,
      reachable: false,
      projects: [],
      count: 0,
      error_code: code,
      error_message: message
    }
  end
end
