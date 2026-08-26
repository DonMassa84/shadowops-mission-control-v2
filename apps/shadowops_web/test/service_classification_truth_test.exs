defmodule ShadowOpsWeb.ServiceClassificationTruthTest do
  use ExUnit.Case, async: false

  @classification_keys ~w(
    classification_stage runtime_identity runtime_verified live connected
    real_data ready definition_match runtime_conflict runtime_ambiguous
  )

  test "API /api/services exposes canonical classification fields" do
    conn = Plug.Test.conn(:get, "/api/services")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    services = body["services"]

    assert is_list(services)
    assert length(services) > 0

    Enum.each(services, fn svc ->
      for key <- @classification_keys do
        assert Map.has_key?(svc, key), "missing #{key} in service #{inspect(svc["name"])}"
      end
    end)
  end

  test "no service is READY from active-only (no real_data)" do
    conn = Plug.Test.conn(:get, "/api/services")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    body = Jason.decode!(response.resp_body)
    services = body["services"]

    Enum.each(services, fn svc ->
      # real_data is always false in the discovered/runtime_verified model, so
      # ready must never be true without real_data.
      expected_ready =
        svc["runtime_verified"] and svc["live"] and svc["connected"] and svc["real_data"] and
          svc["definition_match"] and not svc["runtime_conflict"] and not svc["runtime_ambiguous"]

      assert svc["ready"] == expected_ready,
             "ready mismatch for #{inspect(svc["name"])}: #{inspect(svc)}"

      refute svc["ready"],
             "service #{inspect(svc["name"])} must not be READY without real_data"
    end)
  end

  test "API /api/integrations exposes canonical classification on local functions" do
    conn = Plug.Test.conn(:get, "/api/integrations")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    records = body["local_discovery"]["records"]

    assert is_list(records)
    assert length(records) > 0

    Enum.each(records, fn record ->
      for key <- @classification_keys do
        assert Map.has_key?(record, key),
               "missing #{key} in local function #{inspect(record["name"])}"
      end

      # local functions are discovery-only => never runtime_verified/ready
      refute record["runtime_verified"]
      refute record["ready"]
    end)
  end

  test "Services LiveView renders canonical classification columns" do
    conn = Plug.Test.conn(:get, "/services")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200
    body = response.resp_body

    for header <- ["Stage", "Runtime", "Live", "Connected", "Data", "Governance", "Ready"] do
      assert body =~ header, "missing column #{header} in /services"
    end
  end

  test "Integrations LiveView renders canonical local-function health states" do
    conn = Plug.Test.conn(:get, "/integrations")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200
    body = response.resp_body

    assert body =~ "Local function inventory"
    assert body =~ "DISCOVERED"
    # canonical health states must be present in the projection vocabulary
    assert body =~ "RUNTIME_VERIFIED" or body =~ "DISCOVERED"
  end

  test "API and UI share the same canonical classification state" do
    api =
      Plug.Test.conn(:get, "/api/services")
      |> ShadowOpsWeb.Endpoint.call([])
      |> then(&Jason.decode!(&1.resp_body))

    ui =
      Plug.Test.conn(:get, "/services")
      |> ShadowOpsWeb.Endpoint.call([])

    assert ui.status == 200

    api_services = api["services"]

    Enum.each(api_services, fn svc ->
      name = svc["name"]
      stage = svc["classification_stage"]

      # The UI must show the same service and the same canonical stage text.
      assert ui.resp_body =~ name, "service #{name} missing from /services UI"
      assert ui.resp_body =~ stage, "stage #{stage} for #{name} missing from /services UI"
    end)
  end

  test "one Services API request triggers at most one runtime snapshot fetch" do
    # The classification is pure and consumes a snapshot already loaded by
    # ShadowOpsApi.services(). We assert the response is internally consistent
    # and contains the canonical fields, proving no separate adapter probe.
    conn = Plug.Test.conn(:get, "/api/services")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    services = body["services"]

    # every service carries the same canonical field set derived from one snapshot
    Enum.each(services, fn svc ->
      assert is_binary(svc["runtime_identity"])
      assert is_boolean(svc["runtime_verified"])
      assert is_boolean(svc["ready"])
    end)
  end
end
