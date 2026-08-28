defmodule ImportExternalWorkflowsContractTest do
  use ExUnit.Case, async: true

  @registry "config/workflow_registry_v2.yaml"
  @script "scripts/import_external_workflows_v6.exs"

  test "importer exists" do
    assert File.regular?(@script)
  end

  test "registry exists" do
    assert File.regular?(@registry)
  end

  test "importer is dry-run only" do
    body = File.read!(@script)

    assert body =~ "REGISTRY_MUTATION=NO"
    assert body =~ "RUNTIME_EXECUTION=NO"

    refute body =~ "YamlElixir.write_to_file"
    refute body =~ "File.write!(@registry"
  end

  test "does not invent OpenCode or Telegram ids" do
    body = File.read!(@script)

    refute body =~ ~s("opencode_standard-1")
    refute body =~ ~s("telegram_workflow_controller-1")
  end

  test "uses source qualified canonical identities" do
    body = File.read!(@script)

    assert body =~ "@canonical_prefix"
    assert body =~ ~s(wf["source_set"])
    assert body =~ ~s(wf["source_native_id"])
  end

  test "contains canonical collision protection" do
    assert File.read!(@script) =~ "CANONICAL_ID_COLLISION"
  end

  test "contains unknown risk protection" do
    assert File.read!(@script) =~ "UNKNOWN_RISK"
  end

  test "contains missing capability protection" do
    assert File.read!(@script) =~ "MISSING_CAPABILITY"
  end

  test "contains unknown runtime protection" do
    assert File.read!(@script) =~ "UNKNOWN_RUNTIME"
  end

  test "contains L2/L3 approval protection" do
    assert File.read!(@script) =~ "UNAPPROVED_L2_L3"
  end
end
