defmodule WorkflowEngine.WorkflowIdsTest do
  use ExUnit.Case, async: true

  alias WorkflowEngine.WorkflowIds

  @root Path.expand("../../..", __DIR__)
  @ids_path Path.join(@root, "config/workflow_ids.yaml")

  test "every canonical registry workflow has exactly one immutable global id" do
    assert {:ok, workflows} = WorkflowIds.all()
    ids = YamlElixir.read_from_file!(@ids_path)

    assert length(workflows) == 18

    global_ids = Enum.map(workflows, & &1.id)
    assert Enum.uniq(global_ids) == global_ids
    assert Enum.all?(global_ids, &WorkflowIds.valid?/1)
    assert ids["rules"]["ids_are_immutable"] == true
    assert ids["rules"]["duplicate_ids_forbidden"] == true
  end

  test "canonical IDs resolve through the Elixir contract" do
    assert {:ok, "so:wf:v1:repository-quality"} =
             WorkflowIds.canonical_id("repository_quality")

    assert {:ok, by_key} = WorkflowIds.get("daily_digest")
    assert {:ok, by_id} = WorkflowIds.get("so:wf:v1:daily-digest")
    assert by_key == by_id
    assert by_key.domain == "reporting"
    assert {:error, :not_found} = WorkflowIds.canonical_id("does_not_exist")
  end

  test "federation workflow ids remain unique external references" do
    ids = YamlElixir.read_from_file!(@ids_path)
    federation = Map.fetch!(ids, "federation_workflows")

    global_ids = Enum.map(federation, fn {_key, value} -> Map.fetch!(value, "id") end)

    assert Enum.uniq(global_ids) == global_ids
    assert Enum.all?(global_ids, &String.starts_with?(&1, "so:wf:v1:"))

    assert Enum.all?(federation, fn {_key, value} ->
             value["integration_mode"] == "EXTERNAL_REFERENCE" and
               is_binary(value["source_repository"]) and
               is_binary(value["source_definition"])
           end)
  end

  test "unknown external workflow ids remain explicitly unimported" do
    ids = YamlElixir.read_from_file!(@ids_path)
    sets = Map.fetch!(ids, "external_runtime_sets")

    assert {:ok, opencode} = WorkflowIds.external_set("opencode_standard")
    assert opencode["external_ids_status"] == "NOT_IMPORTED"
    assert opencode["set_id"] == "so:wfset:v1:opencode-standard"

    assert sets["telegram_workflow_controller"]["external_ids_status"] == "NOT_IMPORTED"
    assert ids["rules"]["unknown_external_ids_must_not_be_fabricated"] == true
    assert ids["rules"]["external_ids_require_evidence"] == true
  end
end
