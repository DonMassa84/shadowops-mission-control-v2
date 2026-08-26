defmodule ShadowOpsCore.LocalIntegrationCandidatesTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.{LocalIntegrationCandidates, RuntimeSources}

  setup do
    root =
      Path.join(System.tmp_dir!(), "shadowops_candidates_#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "missing local artifacts remain not configured and non-executable", %{root: root} do
    snapshot = LocalIntegrationCandidates.snapshot(root)

    assert snapshot.status == "NOT_CONFIGURED"
    assert snapshot.counts.total == 10
    assert snapshot.counts.discovered == 0
    assert snapshot.real_data == false
    assert snapshot.reachable == false

    assert Enum.all?(snapshot.records, fn record ->
             record.status == "NOT_CONFIGURED" and
               record.real_data == false and
               record.synthetic == false and
               record.reachable == false and
               record.executable == false and
               record.integration_mode == "REFERENCE_ONLY"
           end)
  end

  test "fixed local evidence promotes only to discovered", %{root: root} do
    service =
      Path.join(root, "DokumentenSystem/09_BOT_GATEWAY/scripts/bot-gateway.service")

    healer = Path.join(root, "DokumentenSystem/07_AUTOMATION/system_healer.sh")

    voice =
      Path.join(root, "DokumentenSystem/07_AUTOMATION/voice_agent/systemd/voice-agent.service")

    Enum.each([service, healer, voice], fn path ->
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "fixture")
    end)

    snapshot = LocalIntegrationCandidates.snapshot(root)

    assert snapshot.status == "DISCOVERED"
    assert snapshot.counts.discovered == 3
    assert snapshot.real_data == true
    assert snapshot.reachable == true

    for id <- ["bot_gateway", "system_healer", "voice_agent"] do
      record = Enum.find(snapshot.records, &(&1.id == id))
      assert record.status == "DISCOVERED"
      assert record.real_data == true
      assert record.reachable == true
      assert record.executable == false
      refute Enum.any?(record.evidence, &String.contains?(&1, root))
    end
  end

  test "child services are evidence only and never become top-level executable actions", %{
    root: root
  } do
    child =
      Path.join(
        root,
        "DokumentenSystem/07_AUTOMATION/documentation_factory/systemd/documentation-factory-watcher.service"
      )

    File.mkdir_p!(Path.dirname(child))
    File.write!(child, "fixture")

    snapshot = LocalIntegrationCandidates.snapshot(root)
    factory = Enum.find(snapshot.records, &(&1.id == "documentation_factory"))

    assert factory.status == "DISCOVERED"
    assert factory.kind == "SERVICE_FAMILY"
    assert factory.evidence == ["documentation-factory-watcher.service"]
    assert factory.executable == false
    assert factory.risk_level == "UNKNOWN"
  end

  test "candidate unit names are not added to the service action allowlist" do
    assert {:error, :service_not_allowlisted} =
             RuntimeSources.service_action("user:bot-gateway.service", "restart")
  end
end
