defmodule ShadowOpsWeb.HighValueWorkflowsTest do
  use ExUnit.Case, async: true

  alias ShadowOpsWeb.HighValueWorkflows

  defp sources(overrides \\ %{}) do
    base = %{
      overview: %{
        readiness: %{state: "READY"},
        system: %{
          status: "ONLINE",
          source: "fixture",
          real_data: true,
          synthetic: false,
          disk: %{used_percent: "42%"},
          ram: %{total_bytes: 100, available_bytes: 50},
          temperatures_c: [50]
        },
        services: %{source: "fixture", services: [%{name: "shadowops", status: "READY"}]},
        security: %{status: "READY", source: "fixture"},
        backups: %{status: "READY", source: "fixture", real_data: true, synthetic: false},
        audit: %{valid: true, source: "fixture"},
        approvals: %{records: []},
        runs: %{records: []},
        career: %{
          status: "READY",
          source: "fixture",
          real_data: true,
          synthetic: false,
          applications: []
        },
        evidence: %{
          artifacts: [
            %{artifact: "projektantrag.pdf", verification_status: "VERIFIED"},
            %{artifact: "stunden.csv", verification_status: "VERIFIED"},
            %{artifact: "kosten.md", verification_status: "VERIFIED"},
            %{artifact: "tests.md", verification_status: "VERIFIED"},
            %{artifact: "abnahme.pdf", verification_status: "VERIFIED"},
            %{artifact: "implementation.md", verification_status: "VERIFIED"},
            %{artifact: "github-ci.md", verification_status: "VERIFIED"},
            %{artifact: "quellen.md", verification_status: "VERIFIED"}
          ]
        }
      },
      ihk_domain: %{status: "READY", source: "fixture", real_data: true, synthetic: false},
      career_domain: %{status: "READY", source: "fixture", real_data: true, synthetic: false},
      release: %{
        branch: "local/all-developments",
        target_branch: "local/all-developments",
        head: "abc",
        certificate_present: true,
        certificate_path: "/tmp/cert",
        certificate_head: "abc",
        certificate: %{
          "HEAD" => "abc",
          "FORMAT" => "PASS",
          "COMPILE" => "PASS",
          "TESTS" => "PASS",
          "CREDO" => "PASS",
          "DIALYZER" => "PASS",
          "SOBELOW" => "PASS",
          "REGISTRY" => "PASS",
          "WORKFLOW_IDS" => "PASS",
          "HEX_AUDIT" => "PASS",
          "PRODUCTION_HANDOFF" => "PASS",
          "MCP_CONTRACT" => "PASS",
          "LOCAL_CODER_CONTRACT" => "PASS"
        }
      }
    }

    deep_merge(base, overrides)
  end

  test "healthy evidence yields green specialized workflows" do
    result = HighValueWorkflows.from_sources(sources())
    assert result.system_doctor.status == "GREEN"
    assert result.release_acceptance.status == "GREEN"
    assert result.ihk_evidence_gate.status == "GREEN"
    assert result.career_control.status == "GREEN"
    assert result.daily_control.workflow_id == "so:wf:v1:daily-control"

    for kind <- [:system_doctor, :release_acceptance, :ihk_evidence_gate, :career_control] do
      assert result[kind].workflow_id == nil
      assert result[kind].registry_status == "NOT_CONFIGURED"
    end
  end

  test "daily control returns max three deterministic actions" do
    bad =
      sources(%{
        overview: %{
          security: %{status: "ERROR", source: "fixture"},
          approvals: %{records: [%{status: "PENDING"}]},
          runs: %{records: [%{status: "FAILED"}]}
        },
        release: %{certificate_present: false, certificate: %{}, certificate_head: nil}
      })

    first = HighValueWorkflows.from_sources(bad).daily_control
    second = HighValueWorkflows.from_sources(bad).daily_control

    assert length(first.next_actions) <= 3

    assert Enum.map(first.next_actions, &{&1.id, &1.score}) ==
             Enum.map(second.next_actions, &{&1.id, &1.score})
  end

  test "missing sources never become green" do
    bad =
      sources(%{
        overview: %{
          backups: %{status: "NOT_CONNECTED", real_data: false, synthetic: false},
          career: %{status: "NOT_CONFIGURED", real_data: false, synthetic: false}
        }
      })

    result = HighValueWorkflows.from_sources(bad)
    refute result.system_doctor.status == "GREEN"
    refute result.career_control.status == "GREEN"
  end

  test "synthetic evidence cannot satisfy real-data checks" do
    bad =
      sources(%{
        overview: %{backups: %{status: "READY", real_data: true, synthetic: true}},
        ihk_domain: %{status: "READY", real_data: true, synthetic: true}
      })

    result = HighValueWorkflows.from_sources(bad)
    refute result.system_doctor.status == "GREEN"
    refute result.ihk_evidence_gate.status == "GREEN"
  end

  test "available IHK artifact is weak, not verified" do
    bad =
      sources(%{
        overview: %{
          evidence: %{
            artifacts: [%{artifact: "projektantrag.pdf", verification_status: "AVAILABLE"}]
          }
        }
      })

    result = HighValueWorkflows.from_sources(bad).ihk_evidence_gate
    assert result.weak_count == 1
    assert result.missing_count == 7
    refute result.status == "GREEN"
  end

  test "career waiting records produce follow-up only from structured evidence" do
    old = DateTime.utc_now() |> DateTime.add(-8 * 86_400, :second) |> DateTime.to_iso8601()

    src =
      sources(%{
        overview: %{
          career: %{
            status: "READY",
            source: "fixture",
            real_data: true,
            synthetic: false,
            applications: [%{id: "company-a", status: "WAITING", updated_at: old}]
          }
        }
      })

    result = HighValueWorkflows.from_sources(src).career_control
    assert Enum.any?(result.next_actions, &String.contains?(&1.id, "followup"))
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, l, r ->
      if is_map(l) and is_map(r), do: deep_merge(l, r), else: r
    end)
  end
end
