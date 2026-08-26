defmodule Mix.Tasks.Shadowops.Chatgpt.Catalog do
  use Mix.Task

  @shortdoc "Projects bounded ChatGPT export metadata into the local federated catalog"

  alias ShadowOpsCore.ChatGPTSource

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    source = ChatGPTSource.snapshot()
    output = ShadowOpsCore.ProjectCatalog.default_path()

    case source do
      %{status: "READY", projects: projects} ->
        payload = %{
          schema_version: "1",
          generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          github_discovery_mode: "UNCHANGED",
          projects: projects
        }

        output |> Path.dirname() |> File.mkdir_p!()
        File.write!(output, Jason.encode!(payload, pretty: true))
        Mix.shell().info("CHATGPT_CATALOG=READY")
        Mix.shell().info("PROJECTS=#{length(projects)}")
        Mix.shell().info("OUTPUT=#{output}")

      %{error_code: code, error_message: message} ->
        Mix.raise("CHATGPT_CATALOG=NOT_CONFIGURED code=#{code} message=#{message}")
    end
  end
end
