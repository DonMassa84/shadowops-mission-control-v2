defmodule WorkflowEngine.WorkflowIdsTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../..", __DIR__)
  @registry_path Path.join(@root, "config/workflow_registry_v2.yaml")
  @ids_path Path.join(@root, "config/workflow_ids.yaml")

  test "every canonical registry workflow has exactly one immutable global id" do
    registry = YamlElixir.read_from_file!(@registry_path)
    ids = YamlElixir.read_from_file!(@ids_path)

    registry_keys = registry |> Map.fetch!("workflows") |> Map.keys() |> MapSet.new()
    id_entries = Map.fetch!(ids, "canonical_workflows")
    id_keys = id_entries |> Map.keys() |> MapSet.new()

    assert id_keys == registry_keys

    global_ids = Enum.map(id_entries, fn {_key, value} -> Map.fetch!(value, "id") end)

    assert Enum.uniq(global_ids) == global_ids
    assert Enum.all?(global_ids, &String.starts_with?(&1, "so:wf:v1:"))
    assert ids["rules"]["ids_are_immutable"] == true
    assert ids["rules"]["duplicate_ids_forbidden"] == true
  end

  test "federation workflow ids are unique external references" do
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

    assert sets["opencode_standard"]["external_ids_status"] == "NOT_IMPORTED"
    assert sets["telegram_workflow_controller"]["external_ids_status"] == "NOT_IMPORTED"
    assert ids["rules"]["unknown_external_ids_must_not_be_fabricated"] == true
    assert ids["rules"]["external_ids_require_evidence"] == true
  end
end
