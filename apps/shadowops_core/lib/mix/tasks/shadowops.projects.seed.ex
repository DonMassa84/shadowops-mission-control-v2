defmodule Mix.Tasks.Shadowops.Projects.Seed do
  @moduledoc false

  use Mix.Task

  @shortdoc "Seeds known ShadowOps projects into the local federated Project Catalog"

  alias ShadowOpsCore.{ProjectCatalog, ProjectCatalogSeed}

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    path = System.get_env("SHADOWOPS_PROJECT_CATALOG") || ProjectCatalog.default_path()
    existing = ProjectCatalog.snapshot(path)

    existing_projects =
      case existing do
        %{status: "READY", projects: projects} when is_list(projects) -> projects
        %{error_code: "SOURCE_MISSING"} -> []
        %{error_code: code, error_message: message} ->
          Mix.raise("PROJECT_CATALOG_SEED=BLOCKED code=#{code} message=#{message}")
      end

    discovery_mode =
      case existing do
        %{github_discovery_mode: mode} when is_binary(mode) -> mode
        _ -> "UNKNOWN"
      end

    payload = ProjectCatalogSeed.payload(existing_projects, discovery_mode)

    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, Jason.encode!(payload, pretty: true))

    verified = ProjectCatalog.snapshot(path)

    Mix.shell().info("PROJECT_CATALOG_SEED=PASS")
    Mix.shell().info("PROJECT_CATALOG=#{path}")
    Mix.shell().info("PROJECTS_TOTAL=#{verified.counts.total}")
    Mix.shell().info("PROJECTS_READY=#{verified.counts.ready}")
    Mix.shell().info("PROJECTS_DISCOVERED=#{verified.counts.discovered}")
    Mix.shell().info("PROJECTS_NOT_CONFIGURED=#{verified.counts.not_configured}")
  end
end
