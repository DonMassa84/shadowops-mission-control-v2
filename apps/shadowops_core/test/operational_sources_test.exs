defmodule ShadowOpsCore.OperationalSourcesTest do
  use ExUnit.Case, async: false

  alias ShadowOpsCore.OperationalSources

  @remote_inventory """
  NAME                       ID              SIZE      MODIFIED
  nemo:latest                72e0adc4e167    2.8 GB    3 weeks ago
  qwen2.5:3b                 357c53fb659c    1.9 GB    3 weeks ago
  """

  test "reachable i7 with real remote model inventory is online" do
    runtime =
      OperationalSources.i7_ai_from(
        %{status: "ONLINE"},
        {:ok, @remote_inventory, %{real_data: true, synthetic: false}}
      )

    assert runtime.status == "READY"
    assert runtime.reachable
    assert runtime.real_data
    refute runtime.synthetic
    assert runtime.record_count == 2

    assert Enum.all?(runtime.models, fn model ->
             model.node == "i7" and model.source == "remote ollama CLI"
           end)
  end

  test "reachable i7 with failed inventory remains degraded" do
    runtime =
      OperationalSources.i7_ai_from(%{status: "ONLINE"}, {:error, {:exit_status, 255, "down"}})

    assert runtime.status == "DEGRADED"
    assert runtime.reachable
    refute runtime.real_data
    assert runtime.error_code == "MODEL_INVENTORY_PROBE_FAILED"
    assert runtime.models == []
  end

  test "unreachable i7 keeps remote Ollama unavailable" do
    runtime =
      OperationalSources.i7_ai_from(
        %{status: "UNAVAILABLE"},
        {:ok, @remote_inventory, %{real_data: true, synthetic: false}}
      )

    assert runtime.status == "UNAVAILABLE"
    refute runtime.reachable
    refute runtime.real_data
    assert runtime.error_code == "NODE_UNREACHABLE"
  end

  test "synthetic or prebuilt inventory cannot make remote Ollama online" do
    synthetic =
      OperationalSources.i7_ai_from(
        %{status: "ONLINE"},
        {:ok, @remote_inventory, %{real_data: false, synthetic: true}}
      )

    prebuilt =
      OperationalSources.i7_ai_from(
        %{status: "ONLINE"},
        {:ok, %{models: [%{name: "hardcoded"}]}, %{real_data: true, synthetic: false}}
      )

    assert synthetic.status == "DEGRADED"
    assert prebuilt.status == "DEGRADED"
    refute synthetic.real_data
    refute prebuilt.real_data
  end

  test "missing WhatsApp source is not connected" do
    path =
      Path.join(System.tmp_dir!(), "missing-whatsapp-#{System.unique_integer([:positive])}.db")

    assert OperationalSources.whatsapp_at(path, DateTime.utc_now()).status == "UNAVAILABLE"
  end

  test "real current WhatsApp data connects, while stale and synthetic-only data do not" do
    root = Path.join(System.tmp_dir!(), "whatsapp-contract-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)

    real = database(root, "real.db", 0)
    connected = OperationalSources.whatsapp_at(real, DateTime.utc_now())
    assert connected.status == "READY"
    assert connected.real_data
    refute connected.synthetic

    stale_time = DateTime.add(DateTime.utc_now(), 8 * 24 * 60 * 60, :second)
    assert OperationalSources.whatsapp_at(real, stale_time).status == "DEGRADED"

    synthetic = database(root, "synthetic.db", 1)
    refute OperationalSources.whatsapp_at(synthetic, DateTime.utc_now()).status == "READY"
  end

  test "optional unconfigured IHK check does not block a healthy Career runtime" do
    root = temporary_root("career")
    runtime = Path.join(root, "career-funnel")
    report = Path.join(root, "LATEST.json")
    missing_project = Path.join(root, "missing-ihk-project")

    File.write!(runtime, "#!/bin/sh\nexit 0\n")
    File.chmod!(runtime, 0o700)

    File.write!(
      report,
      Jason.encode!(%{
        "doctor" => %{"passed" => true},
        "status" => %{
          "runs" => 215,
          "fail_closed" => true,
          "external_actions" => "BLOCKED"
        }
      })
    )

    career = OperationalSources.career_at(runtime, root, report, missing_project)

    assert career.status == "READY"
    assert career.record_count == 215
    assert career.metadata.ihk_workflow.optional
    assert career.metadata.ihk_workflow.configuration_status == "NOT_CONFIGURED"
    assert career.metadata.ihk_workflow.execution_status == "DISABLED_BY_CONFIGURATION"
  end

  test "existing Chroma collection passes integrity and record probes" do
    root = temporary_root("knowledge")
    store = Path.join(root, "chroma.sqlite3")

    sqlite!(
      store,
      "CREATE TABLE collections (id TEXT, name TEXT);" <>
        "CREATE TABLE segments (id TEXT, collection TEXT);" <>
        "CREATE TABLE embeddings (id INTEGER, segment_id TEXT);" <>
        "CREATE TABLE embedding_metadata (id INTEGER, key TEXT, string_value TEXT, int_value INTEGER);" <>
        "INSERT INTO collections VALUES ('c1', 'dokumentensystem');" <>
        "INSERT INTO segments VALUES ('s1', 'c1');" <>
        "INSERT INTO embeddings VALUES (1, 's1');" <>
        "INSERT INTO embedding_metadata VALUES (1, 'document_id', NULL, 7);"
    )

    sources = [
      %{availability: "AVAILABLE", document_count: 3, last_update: "2026-08-23T10:00:00"}
    ]

    knowledge = OperationalSources.knowledge_at(sources, store)

    assert knowledge.status == "READY"
    assert knowledge.vector_store.index_valid
    assert knowledge.vector_store.query_probe == "PASS"
    assert knowledge.indexed_documents_count == 1
    assert knowledge.indexed_chunks_count == 1
  end

  test "missing vector store remains degraded" do
    root = temporary_root("missing-knowledge")
    sources = [%{availability: "AVAILABLE", document_count: 3, last_update: nil}]
    knowledge = OperationalSources.knowledge_at(sources, Path.join(root, "missing.sqlite3"))

    assert knowledge.status == "DEGRADED"
    assert knowledge.error_code == "VECTOR_STORE_NOT_CONNECTED"
  end

  test "backup inventory ignores sidecars and verifies the latest database content" do
    root = temporary_root("backups")
    database = Path.join(root, "whatsapp_agent_20260823.db")
    sidecar = database <> "-shm"

    sqlite!(
      database,
      "CREATE TABLE captured_messages (id INTEGER); INSERT INTO captured_messages VALUES (1);"
    )

    File.write!(sidecar, "newer sidecar")
    backup = OperationalSources.backups_at(root)

    assert backup.status == "READY"
    assert backup.metadata.last_backup == Path.basename(database)
    assert backup.metadata.content_records == 1
    assert backup.metadata.verification_result == "PASS"
    assert byte_size(backup.metadata.checksum_sha256) == 64
  end

  defp database(root, name, synthetic) do
    path = Path.join(root, name)

    {_, 0} =
      System.cmd("sqlite3", [
        path,
        "CREATE TABLE captured_messages (id INTEGER, synthetic INTEGER); INSERT INTO captured_messages VALUES (1, #{synthetic});"
      ])

    File.chmod!(path, 0o600)
    path
  end

  defp temporary_root(name) do
    root = Path.join(System.tmp_dir!(), "shadowops-#{name}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    root
  end

  defp sqlite!(path, sql) do
    assert {_, 0} = System.cmd("sqlite3", [path, sql], stderr_to_stdout: true)
    path
  end
end
