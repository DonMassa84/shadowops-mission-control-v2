defmodule ShadowOpsCore.GitHubActionsAdapterTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.Adapters.GitHubActionsAdapter
  alias ShadowOpsCore.WorkflowManifest

  @repository "DonMassa84/shadowops-mission-control-v2"
  @ref "integration/real-github-source-2026-08-27"
  @definition ".github/workflows/product-release-gate.yml"

  test "approved execution dispatches the registered workflow through gh" do
    runner = fn
      "gh",
      [
        "workflow",
        "run",
        @definition,
        "--repo",
        @repository,
        "--ref",
        @ref
      ],
      [stderr_to_stdout: true] ->
        {"", 0}
    end

    assert {:ok, result} =
             GitHubActionsAdapter.run(
               manifest(),
               %{"repository_ref" => @repository, "ref" => @ref, "inputs" => %{}},
               %{policy_decision: "APPROVED", github_runner: runner}
             )

    assert result.accepted
    assert result.real_data
    refute result.synthetic
    assert result.repository == @repository
    assert result.ref == @ref
    assert result.definition == @definition
  end

  test "execution remains fail closed without an approved policy decision" do
    assert {:error, :policy_decision_required} =
             GitHubActionsAdapter.run(
               manifest(),
               %{"repository_ref" => @repository, "ref" => @ref},
               %{}
             )
  end

  test "workflow dispatch rejects untrusted input shapes" do
    runner = fn _, _, _ -> {"", 0} end

    assert {:error, :invalid_github_workflow_input} =
             GitHubActionsAdapter.run(
               manifest(),
               %{
                 "repository_ref" => @repository,
                 "ref" => @ref,
                 "inputs" => %{"unsafe key" => "value"}
               },
               %{policy_decision: "APPROVED", github_runner: runner}
             )
  end

  test "real GitHub connectivity cannot hide registry definition drift" do
    # Create a local overlay with drift: workflow configured but definition file missing
    drift_overlay = %{
      "workflows" => %{
        "drift_test" => %{
          "type" => "system",
          "domain" => "ci",
          "status" => "active",
          "runtime" => "github_actions",
          "definition" => ".github/workflows/nonexistent-workflow.yml",
          "responsibility" => ["test_drift"]
        }
      }
    }

    drift_path = Path.join(System.tmp_dir!(), "drift_overlay_#{System.unique_integer()}.json")
    File.write!(drift_path, Jason.encode!(drift_overlay))

    runner = fn
      "gh", ["api", "repos/#{@repository}", "--jq", ".full_name"], [stderr_to_stdout: true] ->
        {@repository <> "\n", 0}
    end

    status =
      GitHubActionsAdapter.status(
        repository: @repository,
        runner: runner,
        local_workflow_overlay: drift_path
      )

    File.rm!(drift_path)

    assert status.state == "DEGRADED"
    assert status.repository == @repository
    assert status.reason == "github_workflow_definition_drift"
    assert status.definitions_valid < status.configured
  end

  defp manifest do
    %WorkflowManifest{
      id: "product_release_gate",
      name: "Product release gate",
      source: "github_actions",
      runtime: %{type: "github_actions", value: "github_actions"},
      executor: "GitHubActionsAdapter",
      target: "github",
      risk_level: "L2",
      approval_required: true,
      inputs: [],
      outputs: [],
      connectors: %{},
      privacy: %{raw_data: "local_only", github: "metadata_only"},
      evidence_required: true,
      synthetic: false,
      metadata: %{registry_status: "active", definition: @definition}
    }
  end
end
