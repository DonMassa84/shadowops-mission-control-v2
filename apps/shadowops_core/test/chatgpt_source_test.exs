defmodule ShadowOpsCore.ChatGPTSourceTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.ChatGPTSource

  test "fails closed when no source is configured" do
    snapshot = ChatGPTSource.snapshot(nil)

    assert snapshot.status == "NOT_CONFIGURED"
    assert snapshot.health == "UNAVAILABLE"
    assert snapshot.real_data == false
    assert snapshot.reachable == false
    assert snapshot.projects == []
    assert snapshot.error_code == "SOURCE_MISSING"
  end

  test "fails closed for unsupported export directory" do
    dir = tmp_dir!("empty")

    snapshot = ChatGPTSource.snapshot(dir)

    assert snapshot.status == "NOT_CONFIGURED"
    assert snapshot.projects == []
    assert snapshot.error_code == "SOURCE_MISSING"
  end

  test "projects.json yields bounded truthful project metadata only" do
    dir = tmp_dir!("projects")

    File.write!(
      Path.join(dir, "projects.json"),
      Jason.encode!(%{
        "projects" => [
          %{
            "id" => "project-1",
            "name" => "Mission Control",
            "secret" => "must-not-leak",
            "messages" => [%{"content" => "private raw message"}]
          }
        ]
      })
    )

    snapshot = ChatGPTSource.snapshot(dir)

    assert snapshot.status == "READY"
    assert snapshot.health == "HEALTHY"
    assert snapshot.real_data == true
    assert snapshot.synthetic == false
    assert snapshot.reachable == true
    assert snapshot.count == 1

    [project] = snapshot.projects
    assert project.id == "project-1"
    assert project.name == "Mission Control"
    assert project.source_type == "chatgpt_library_project"
    assert project.status == "READY"
    assert project.integration_mode == "REFERENCE_ONLY"
    assert project.content_ingested == false
    refute Map.has_key?(project, :secret)
    refute Map.has_key?(project, :messages)
  end

  test "conversations export derives distinct project references without raw content" do
    dir = tmp_dir!("conversations")

    File.write!(
      Path.join(dir, "conversations.json"),
      Jason.encode!([
        %{
          "id" => "conversation-1",
          "project_id" => "project-1",
          "project_name" => "Mission Control",
          "mapping" => %{"raw" => "discard me"}
        },
        %{
          "id" => "conversation-2",
          "project" => %{"id" => "project-1", "name" => "Mission Control"},
          "mapping" => %{"raw" => "discard me too"}
        }
      ])
    )

    snapshot = ChatGPTSource.snapshot(dir)

    assert snapshot.status == "READY"
    assert snapshot.count == 1
    [project] = snapshot.projects
    assert project.id == "project-1"
    assert project.name == "Mission Control"
    refute Map.has_key?(project, :mapping)
  end

  test "invalid JSON fails closed" do
    dir = tmp_dir!("invalid")
    File.write!(Path.join(dir, "projects.json"), "{invalid")

    snapshot = ChatGPTSource.snapshot(dir)

    assert snapshot.status == "NOT_CONFIGURED"
    assert snapshot.projects == []
    assert snapshot.error_code == "INVALID_JSON"
  end

  defp tmp_dir!(suffix) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "shadowops-chatgpt-#{suffix}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end
end
