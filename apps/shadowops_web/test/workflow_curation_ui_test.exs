defmodule ShadowOpsWeb.WorkflowCurationUiTest do
  use ExUnit.Case, async: false

  test "integrations API exposes the workflow production-readiness funnel" do
    conn = Plug.Test.conn(:get, "/api/integrations")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    curation = body["workflow_curation"]

    assert is_map(curation)
    assert curation["source_type"] == "LOCAL_WORKFLOW_CURATION"
    assert curation["synthetic"] == false

    assert curation["lifecycle"] == [
             "DISCOVERED",
             "NORMALIZED",
             "CONNECTED",
             "TESTED",
             "PRODUCTION_READY"
           ]

    for field <- [
          "workflow_found_count",
          "workflow_unique_count",
          "workflow_potential_duplicate_count",
          "workflow_duplicate_group_count",
          "workflow_normalized_count",
          "workflow_connected_count",
          "workflow_tested_count",
          "workflow_production_ready_count"
        ] do
      assert is_integer(body[field])
      assert body[field] >= 0
    end

    assert body["workflow_unique_count"] <= body["workflow_found_count"]
    assert body["workflow_production_ready_count"] <= body["workflow_tested_count"]
    assert body["workflow_tested_count"] <= body["workflow_connected_count"]
    assert body["workflow_connected_count"] <= body["workflow_normalized_count"]
  end

  test "integrations page presents a curated capability library instead of raw-count marketing" do
    conn = Plug.Test.conn(:get, "/integrations")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200
    assert response.resp_body =~ "Capability library"
    assert response.resp_body =~ "Workflow production readiness funnel"
    assert response.resp_body =~ "01 · Found"
    assert response.resp_body =~ "02 · Unique"
    assert response.resp_body =~ "03 · Normalized"
    assert response.resp_body =~ "04 · Connected"
    assert response.resp_body =~ "05 · Tested"
    assert response.resp_body =~ "06 · Production ready"
    assert response.resp_body =~ "Curated workflow library"
    assert response.resp_body =~ "Required systems"
    assert response.resp_body =~ "Lifecycle"
  end

  test "curation styling is responsive and includes the readiness funnel surface" do
    css = File.read!(Path.expand("../priv/static/assets/mission-control-command.css", __DIR__))

    assert css =~ ".mc-curation-funnel"
    assert css =~ ".mc-curation-stage"
    assert css =~ ".mc-category-chip"
    assert css =~ "grid-template-columns:repeat(6"
    assert css =~ "@media(max-width:760px)"
    assert css =~ "@media(max-width:520px)"
  end
end
