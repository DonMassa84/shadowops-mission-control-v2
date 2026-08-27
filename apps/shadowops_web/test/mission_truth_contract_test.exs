defmodule ShadowOpsWeb.MissionTruthContractTest do
  use ExUnit.Case, async: false

  alias ShadowOpsWeb.{IntegrationCatalog, MissionBrief, SourceRegistry}

  test "import evidence fails closed when real_data and reachable are omitted" do
    previous = System.get_env("SHADOWOPS_IMPORT_DIR")

    root =
      Path.join(System.tmp_dir!(), "shadowops-source-truth-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)

    on_exit(fn ->
      File.rm_rf(root)

      if previous do
        System.put_env("SHADOWOPS_IMPORT_DIR", previous)
      else
        System.delete_env("SHADOWOPS_IMPORT_DIR")
      end
    end)

    System.put_env("SHADOWOPS_IMPORT_DIR", root)

    File.write!(
      Path.join(root, "gmail.json"),
      Jason.encode!(%{"status" => "READY", "record_count" => 3})
    )

    source = SourceRegistry.snapshot("gmail")

    assert source.status == "READY"
    assert source.real_data == false
    assert source.reachable == false
  end

  test "optional integrations cannot make degraded required core healthy" do
    records = [
      %{name: "System", scope: "core", status: "READY"},
      %{name: "Workflows", scope: "core", status: "UNAVAILABLE"},
      %{
        name: "Optional Import",
        scope: "import",
        status: "READY",
        real_data: true,
        reachable: true
      }
    ]

    summary = IntegrationCatalog.health_summary(records)

    assert summary.status == "DEGRADED"
    assert summary.required_ready == 1
    assert summary.required_total == 2
    assert summary.optional_ready == 1
  end

  test "external and import sources need explicit real and reachable evidence to count positive" do
    refute IntegrationCatalog.positive?(%{
             scope: "import",
             status: "READY",
             real_data: false,
             reachable: false
           })

    assert IntegrationCatalog.positive?(%{
             scope: "external",
             status: "READY",
             real_data: true,
             reachable: true
           })
  end

  test "mission priority is deterministic and blockers outrank configured focus" do
    overview = %{
      readiness: %{state: "FAIL"},
      approvals: %{records: [%{status: "PENDING"}], source: "approval store"},
      services: %{services: [%{status: "DEGRADED"}], source: "service runtime"},
      nodes: %{
        records: [%{status: "OFFLINE", metadata: %{logical: false}}],
        source: "node runtime"
      }
    }

    integrations = %{
      status: "DEGRADED",
      required_core_ready_count: 7,
      required_core_count: 9,
      source: "integration catalog"
    }

    brief = MissionBrief.build(overview, ready_jobs(), integrations, focus())

    assert Enum.map(brief.actions, & &1.title) == [
             "Review pending approvals",
             "Restore runtime readiness",
             "Repair required integrations"
           ]
  end

  test "healthy runtime falls back to configured focus actions without inventing tasks" do
    overview = %{
      readiness: %{state: "READY"},
      approvals: %{records: [], source: "approval store"},
      services: %{services: [%{status: "READY"}], source: "service runtime"},
      nodes: %{
        records: [%{status: "ONLINE", metadata: %{logical: false}}],
        source: "node runtime"
      }
    }

    integrations = %{
      status: "READY",
      required_core_ready_count: 9,
      required_core_count: 9,
      source: "integration catalog"
    }

    brief = MissionBrief.build(overview, ready_jobs(), integrations, focus())

    assert brief.mission.title == "KEEP YOUR MISSION"
    assert brief.mission.source == "LEARNING_FOCUS"

    assert Enum.map(brief.actions, & &1.title) == [
             "SELECTION > SEDUCTION",
             "OPTIONS > FIXATION",
             "KEIN HINTERHERLAUFEN"
           ]

    assert Enum.all?(brief.actions, &(&1.source == "LEARNING_FOCUS"))
  end

  defp ready_jobs,
    do: %{status: "READY", source: "job queue", error_message: nil, record_count: 0}

  defp focus do
    %{
      "availability" => "AVAILABLE",
      "source" => "LEARNING_FOCUS",
      "goal" => %{"title" => "KEEP YOUR MISSION", "smart" => "Configured mission"},
      "current" => %{
        "title" => "SELECTION > SEDUCTION",
        "instruction" => "Configured current instruction",
        "done_when" => "Configured completion condition"
      },
      "next" => ["OPTIONS > FIXATION", "KEIN HINTERHERLAUFEN", "KEINE KÜNSTLICHE DISTANZ"]
    }
  end
end
