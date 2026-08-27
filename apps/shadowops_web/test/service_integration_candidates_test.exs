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
    assert response.resp_body =~ "Workflow IDs"
    assert response.resp_body =~ "Local function inventory"
    assert response.resp_body =~ "Reference only"
  end

  test "integrations API and page expose measured knowledge sources separately from RAG readiness" do
    conn = Plug.Test.conn(:get, "/api/integrations")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    sources = body["knowledge_sources"]

    assert is_list(sources)
    assert body["knowledge_source_count"] == 3
    assert length(sources) == 3

    assert Enum.map(sources, & &1["name"]) == [
             "ProofFlow-Obsidian-Vault",
             "shadowops-knowledge",
             "workflow-knowledge"
           ]

    assert body["knowledge_document_count"] ==
             Enum.sum(Enum.map(sources, & &1["document_count"]))

    assert Enum.all?(sources, fn source ->
             source["synthetic"] == false and
               is_integer(source["document_count"]) and
               source["document_count"] >= 0
           end)

    page = ShadowOpsWeb.Endpoint.call(Plug.Test.conn(:get, "/integrations"), [])

    assert page.status == 200
    assert page.resp_body =~ "Knowledge docs"
    assert page.resp_body =~ "Knowledge sources"
    assert page.resp_body =~ "ProofFlow-Obsidian-Vault"
    assert page.resp_body =~ "shadowops-knowledge"
    assert page.resp_body =~ "workflow-knowledge"
    assert page.resp_body =~ "RAG readiness remains separate"
  end
end
