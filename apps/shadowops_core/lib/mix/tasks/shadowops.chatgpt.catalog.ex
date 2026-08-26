defmodule Mix.Tasks.Shadowops.Chatgpt.Catalog do
  use Mix.Task

  @shortdoc "Projects verified local ChatGPT evidence into ShadowOps metadata surfaces"

  alias ShadowOpsCore.ChatGPTSource
  alias ShadowOpsCore.ProjectCatalog

  @chatgpt_source_type "chatgpt_library_project"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    source = ChatGPTSource.snapshot()
    catalog_output = ProjectCatalog.default_path()

    case source do
      %{status: "READY", projects: chatgpt_projects} ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()
        existing = ProjectCatalog.snapshot(catalog_output)

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

        catalog_payload = %{
          schema_version: existing.schema_version || "1",
          generated_at: now,
          github_discovery_mode: existing.github_discovery_mode || "UNKNOWN",
          projects: merged
        }

        domain_payload = %{
          status: "READY",
          health: "HEALTHY",
          summary: "Verified local ChatGPT project metadata connected",
          open_items: 0,
          next_deadline: nil,
          updated_at: now,
          classification: "PRIVATE_LOCAL"
        }

        import_payload = %{
          status: "READY",
          health: "HEALTHY",
          adapter: "local_chatgpt_project_export",
          last_sync: now,
          record_count: length(chatgpt_projects),
          real_data: true,
          synthetic: false,
          reachable: true
        }

        write_json!(catalog_output, catalog_payload)
        write_json!(domain_manifest_path(), domain_payload)
        write_json!(import_evidence_path(), import_payload)

        Mix.shell().info("CHATGPT_EVIDENCE=READY")
        Mix.shell().info("CHATGPT_PROJECTS=#{length(chatgpt_projects)}")
        Mix.shell().info("TOTAL_PROJECTS=#{length(merged)}")
        Mix.shell().info("CATALOG=#{catalog_output}")
        Mix.shell().info("DOMAIN=#{domain_manifest_path()}")
        Mix.shell().info("IMPORT=#{import_evidence_path()}")

      %{error_code: code, error_message: message} ->
        Mix.raise("CHATGPT_EVIDENCE=NOT_CONFIGURED code=#{code} message=#{message}")
    end
  end

  defp write_json!(path, payload) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, Jason.encode!(payload, pretty: true))
  end

  defp domain_manifest_path do
    System.get_env("SHADOWOPS_CHATGPT_MANIFEST") ||
      Path.join([
        System.user_home!(),
        ".local",
        "share",
        "shadowops",
        "domains",
        "chatgpt.json"
      ])
  end

  defp import_evidence_path do
    root =
      System.get_env("SHADOWOPS_IMPORT_DIR") ||
        Path.join([System.user_home!(), ".local", "share", "shadowops", "imports"])

    Path.join(root, "chatgpt_project.json")
  end
end
