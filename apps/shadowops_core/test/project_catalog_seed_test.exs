defmodule ShadowOpsCore.ProjectCatalogSeedTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.ProjectCatalogSeed

  test "known project seed is metadata-only, deterministic and non-positive" do
    projects = ProjectCatalogSeed.projects()

    expected_ids =
      MapSet.new(~w(
        shadowops:mission-control-v2
        shadowops:data-fabric
        shadowops:ontology-v3
        shadowops:electron-mission-control
        shadowops:workflow-federation
        shadowops:whatsapp-agent
        shadowops:facebook-analytics
        shadowops:messenger
        shadowops:telegram-controller
        shadowops:local-ai
        shadowops:i7-control
        shadowops:knowledge
        shadowops:evidence
        shadowops:career
        shadowops:backups
        shadowops:reporting
        shadowops:opencode-standard
        ihk:zero-trust-project
        chatgpt:local-project
      ))

    assert length(projects) == 19
    assert Enum.map(projects, & &1.id) |> Enum.uniq() |> length() == 19
    assert MapSet.new(projects, & &1.id) == expected_ids

    assert Enum.all?(projects, fn project ->
             project.status in ["DISCOVERED", "NOT_CONFIGURED"] and
               project.real_data == false and
               project.synthetic == false and
               project.reachable == false and
               project.content_ingested == false and
               project.integration_mode == "REFERENCE_ONLY"
           end)

    chatgpt = Enum.find(projects, &(&1.id == "chatgpt:local-project"))
    assert chatgpt.status == "NOT_CONFIGURED"
  end

  test "existing evidenced record wins over a seed record with the same stable id" do
    existing = [
      %{
        id: "shadowops:mission-control-v2",
        name: "ShadowOps Mission Control V2",
        domain: "shadowops",
        source_type: "local_repo",
        status: "READY",
        real_data: true,
        synthetic: false,
        reachable: true,
        content_ingested: false
      }
    ]

    merged = ProjectCatalogSeed.merge(existing)

    assert length(merged) == 19

    mission_control = Enum.find(merged, &(&1.id == "shadowops:mission-control-v2"))
    assert mission_control.status == "READY"
    assert mission_control.source_type == "local_repo"
    assert mission_control.real_data == true
    assert mission_control.reachable == true
  end

  test "payload never promotes discovery seed records to ready" do
    payload = ProjectCatalogSeed.payload([], "UNKNOWN", "2026-08-26T00:00:00Z")

    assert payload.schema_version == 1
    assert payload.synthetic == false
    assert payload.generated_at == "2026-08-26T00:00:00Z"
    refute Enum.any?(payload.projects, &(&1.status == "READY"))
  end
end
