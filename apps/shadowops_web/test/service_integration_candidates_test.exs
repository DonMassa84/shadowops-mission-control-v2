defmodule ShadowOpsWeb.ServiceIntegrationCandidatesTest do
  use ExUnit.Case, async: false

  test "services API exposes bounded read-only integration candidates" do
    conn = Plug.Test.conn(:get, "/api/services")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    candidates = body["integration_candidates"]

    assert is_map(candidates)
    assert candidates["source_type"] == "LOCAL_BOUNDED_FOLDER_DISCOVERY"
    assert candidates["synthetic"] == false
    assert candidates["counts"]["known_total"] == 10
    assert candidates["counts"]["total"] >= 10
    assert candidates["max_auto_records"] == 250

    assert Enum.all?(candidates["records"], fn record ->
             record["executable"] == false and
               record["integration_mode"] == "REFERENCE_ONLY" and
               record["risk_level"] == "UNKNOWN" and
               record["runtime_verified"] == false and
               record["governance_mapped"] == false and
               not String.starts_with?(record["source_ref"], "/")
           end)
  end

  test "services page separates discovered candidates from governed runtime controls" do
    conn = Plug.Test.conn(:get, "/services")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200
    assert response.resp_body =~ "Local integration candidates"
    assert response.resp_body =~ "additional entrypoints auto-discovered"
    assert response.resp_body =~ "actions disabled for all candidate records"
    assert response.resp_body =~ "Open source"
    assert response.resp_body =~ "Bot Gateway"
    assert response.resp_body =~ "System Healer"
  end

  test "integrations page exposes the local function inventory without granting execution" do
    conn = Plug.Test.conn(:get, "/integrations")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200
    assert response.resp_body =~ "Local functions"
    assert response.resp_body =~ "Local function inventory"
    assert response.resp_body =~ "Reference only"
  end
end
