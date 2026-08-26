defmodule Mix.Tasks.Shadowops.Chatgpt.Catalog do
  use Mix.Task

  @shortdoc "Projects bounded ChatGPT export metadata into the local federated catalog"

  alias ShadowOpsCore.ChatGPTSource
  alias ShadowOpsCore.ProjectCatalog

  @chatgpt_source_type "chatgpt_library_project"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    source = ChatGPTSource.snapshot()
    output = ProjectCatalog.default_path()

    case source do
      %{status: "READY", projects: chatgpt_projects} ->
        existing = ProjectCatalog.snapshot(output)

        existing_projects =
          case existing do
            %{status: "READY", projects: projects} when is_list(projects) -> projects
            _ -> []
          end

        merged =
          ProjectCatalog.merge_provider_projects(
            existing_projects,
            chatgpt_projects,
            @chatgpt_source_type
          )

        payload = %{
          schema_version: existing.schema_version || "1",
          generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          github_discovery_mode: existing.github_discovery_mode || "UNKNOWN",
          projects: merged
        }

        output |> Path.dirname() |> File.mkdir_p!()
        File.write!(output, Jason.encode!(payload, pretty: true))
        Mix.shell().info("CHATGPT_CATALOG=READY")
        Mix.shell().info("CHATGPT_PROJECTS=#{length(chatgpt_projects)}")
        Mix.shell().info("TOTAL_PROJECTS=#{length(merged)}")
        Mix.shell().info("OUTPUT=#{output}")

      %{error_code: code, error_message: message} ->
        Mix.raise("CHATGPT_CATALOG=NOT_CONFIGURED code=#{code} message=#{message}")
    end
  end
end
