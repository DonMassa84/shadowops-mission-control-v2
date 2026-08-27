defmodule ShadowOpsWeb.ProductionPlatformTest do
  use ExUnit.Case, async: false

  alias ShadowOpsWeb.{
    IntegrationCatalog,
    PrometheusExporter,
    RuntimeOverview,
    RuntimeSnapshotCache
  }

  alias ShadowOpsCore.RuntimeSources

  setup do
    if Process.whereis(RuntimeSnapshotCache), do: RuntimeSnapshotCache.clear()
    :ok
  end

  test "integration catalog never marks synthetic state as positive" do
    catalog = IntegrationCatalog.snapshot()

    assert catalog.synthetic == false
    assert is_list(catalog.records)
    assert catalog.record_count == length(catalog.records)

    Enum.each(catalog.records, fn item ->
      if IntegrationCatalog.positive?(item) do
        refute item.synthetic
      end
    end)
  end

  test "runtime overview always exposes the control-plane shape" do
    overview = RuntimeOverview.snapshot()

    for key <- [
          :readiness,
          :system,
          :workflows,
          :runs,
          :services,
          :nodes,
          :agents,
          :ai,
          :approvals,
          :audit,
          :security,
          :knowledge,
          :evidence,
          :connectors,
          :social,
          :career,
          :backups,
          :legal
        ] do
      assert is_map(Map.fetch!(overview, key))
    end

    assert overview.readiness.state in ["READY", "FAIL"]
    assert is_list(overview.connectors.records)
  end

  test "runtime snapshot cache reuses a fresh projection" do
    owner = self()
    key = {:production_platform_test, System.unique_integer([:positive])}

    first =
      RuntimeSnapshotCache.fetch(key, fn ->
        send(owner, :snapshot_built)
        %{status: "READY", synthetic: false}
      end)

    assert_receive :snapshot_built
    assert first.status == "READY"

    second =
      RuntimeSnapshotCache.fetch(key, fn ->
        send(owner, :snapshot_rebuilt)
        %{status: "ERROR", synthetic: false}
      end)

    refute_receive :snapshot_rebuilt, 50
    assert second == first
  end

  test "knowledge probe failure remains unavailable while source measurement stays factual" do
    expected_sources = RuntimeSources.knowledge_sources()

    knowledge = RuntimeOverview.project_probe_result(:knowledge, {:exit, :timeout})

    assert knowledge.status == "UNAVAILABLE"
    assert knowledge.real_data == false
    assert knowledge.reachable == false
    assert knowledge.record_count == nil
    assert knowledge.source_measurement_complete == true
    assert knowledge.source_measurement_status == "AVAILABLE"
    assert length(knowledge.sources) == length(expected_sources)
  end

  test "transient knowledge failure is not cached" do
    incomplete = %{
      knowledge: %{
        status: "UNAVAILABLE",
        source_measurement_complete: false,
        sources: [],
        error_code: "SOURCE_TIMEOUT"
      }
    }

    owner = self()
    key = {:knowledge_incomplete_test, System.unique_integer([:positive])}

    assert RuntimeSnapshotCache.fetch(key, fn -> incomplete end) == incomplete

    complete = %{knowledge: %{status: "READY", source_measurement_complete: true, sources: []}}

    assert RuntimeSnapshotCache.fetch(
             key,
             fn ->
               send(owner, :complete_snapshot_built)
               complete
             end
           ) == complete

    assert_receive :complete_snapshot_built
  end

  test "prometheus exporter exposes control-plane integration metrics" do
    metrics = PrometheusExporter.render()

    assert metrics =~ "shadowops_integrations_total"
    assert metrics =~ "shadowops_integrations_positive"
    assert metrics =~ "shadowops_integration_status"
    assert metrics =~ "shadowops_integration_real_data"
    assert metrics =~ "shadowops_integration_reachable"
    assert metrics =~ "shadowops_integration_synthetic"
  end
end
