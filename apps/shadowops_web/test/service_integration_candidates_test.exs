defmodule ShadowOpsWeb.ServiceIntegrationCandidatesTest do
  use ExUnit.Case, async: false

  test "services API exposes bounded read-only integration candidates" do
    conn = Plug.Test.conn(:get, "/api/services")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    candidates = body["integration_candidates"]

    assert is_map(candidates)
    assert candidates["source_type"] == "LOCAL_FIXED_PATH_DISCOVERY"
    assert candidates["synthetic"] == false
    assert candidates["counts"]["total"] == 10

    assert Enum.all?(candidates["records"], fn record ->
             record["executable"] == false and
               record["integration_mode"] == "REFERENCE_ONLY" and
               record["risk_level"] == "UNKNOWN" and
               not String.starts_with?(record["source_ref"], "/")
           end)
  end

  test "services page separates candidates from governed runtime controls" do
    conn = Plug.Test.conn(:get, "/services")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200
    assert response.resp_body =~ "Local integration candidates"
    assert response.resp_body =~ "REFERENCE_ONLY"
    assert response.resp_body =~ "Bot Gateway"
    assert response.resp_body =~ "System Healer"
  end
end
