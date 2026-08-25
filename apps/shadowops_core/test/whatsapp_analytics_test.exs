defmodule ShadowOps.Social.WhatsAppAnalyticsTest do
  use ExUnit.Case, async: false

  alias ShadowOps.Social.WhatsAppAnalytics

  @real_source "/home/schattenmacher/social-exports/whatsapp/WhatsApp Chat Existing Workflow.txt"

  test "missing source fails closed before normalize, analysis, or audit" do
    root = temporary_root("missing")
    source = Path.join(root, "missing.txt")

    assert {:error, error} =
             WhatsAppAnalytics.load(
               source_path: source,
               state_path: Path.join(root, "aggregate.json"),
               audit?: false
             )

    assert error.code == "SOURCE_MISSING"
    refute File.exists?(Path.join(root, "aggregate.json"))
  end

  test "known synthetic fixture signatures are rejected" do
    root = temporary_root("synthetic")
    source = Path.join(root, "synthetic.txt")
    File.write!(source, "[23.08.26, 10:11:12] Fixture: [DRY_RUN] synthetic event\n")

    assert {:error, error} =
             WhatsAppAnalytics.load(
               source_path: source,
               state_path: Path.join(root, "aggregate.json"),
               audit?: false
             )

    assert error.code == "SYNTHETIC_SOURCE"
    refute File.exists?(Path.join(root, "aggregate.json"))
  end

  test "malformed export fails closed before persistence or audit" do
    root = temporary_root("malformed")
    source = Path.join(root, "malformed.txt")
    state_path = Path.join(root, "aggregate.json")
    File.write!(source, "not a WhatsApp export record\n")

    assert {:error, error} =
             WhatsAppAnalytics.load(
               source_path: source,
               state_path: state_path,
               audit?: false
             )

    assert error.code == "SOURCE_PARSE_FAILED"
    refute File.exists?(state_path)
  end

  if File.regular?(@real_source) do
    test "real export is idempotently ingested, normalized, analyzed, and audited" do
      root = temporary_root("real")
      state_path = Path.join(root, "aggregate.json")
      audit_path = Path.join(root, "audit.jsonl")
      configure_audit(audit_path)

      assert {:ok, first} =
               WhatsAppAnalytics.load(source_path: @real_source, state_path: state_path)

      assert first.privacy == "aggregate_only"
      assert first.source.synthetic == false
      assert first.source.parseable == true
      assert first.ingest.status == "PASS"
      assert first.normalize.status == "PASS"
      assert first.analysis.status == "PASS"
      assert first.analysis.message_count > 0
      assert first.normalize.record_count == first.analysis.message_count
      assert first.analysis.conversation_count > 0
      assert first.analysis.direction_unknown_count == first.analysis.message_count
      assert first.audit.status == "PASS"
      assert first.audit.hash_chain == "PASS"
      assert first.ingest_result == "IMPORTED"

      expected_sha = @real_source |> File.read!() |> sha256()
      assert first.source.sha256 == expected_sha
      assert String.starts_with?(first.provenance.trace_id, "wa_trace_")
      assert byte_size(first.provenance.normalized_digest) == 64

      entries_after_first = ShadowOpsCore.Audit.list(100)
      assert length(entries_after_first) == 3
      assert {:ok, %{valid: true, entries: 3}} = ShadowOpsCore.Audit.verify()

      assert {:ok, second} =
               WhatsAppAnalytics.load(source_path: @real_source, state_path: state_path)

      assert second.ingest_result == "UNCHANGED"
      assert second.provenance.trace_id == first.provenance.trace_id
      assert second.provenance.normalized_digest == first.provenance.normalized_digest
      assert second.analysis == first.analysis
      assert length(ShadowOpsCore.Audit.list(100)) == 3

      whatsapp_events = ShadowOpsCore.Audit.list(100)

      assert Enum.sort(Enum.map(whatsapp_events, & &1["resource"])) ==
               ~w(whatsapp_analysis whatsapp_connector whatsapp_import)

      assert Enum.all?(whatsapp_events, &(&1["metadata"]["privacy"] == "aggregate_only"))

      artifact = state_path |> File.read!() |> Jason.decode!()
      assert get_in(artifact, ["analysis", "message_count"]) == first.analysis.message_count
      refute Enum.any?(all_keys(artifact), &(&1 in ~w(body sender message_text raw_messages)))

      assert {:ok, stat} = File.stat(state_path)
      assert Bitwise.band(stat.mode, 0o777) == 0o600
    end

    test "unchanged ingest requires matching WhatsApp audit evidence, not only a valid chain" do
      root = temporary_root("audit-provenance")
      state_path = Path.join(root, "aggregate.json")
      configure_audit(Path.join(root, "audit.jsonl"))

      assert {:ok, first} =
               WhatsAppAnalytics.load(source_path: @real_source, state_path: state_path)

      artifact = state_path |> File.read!() |> Jason.decode!()
      tampered = put_in(artifact, ["audit", "event_ids"], [])
      File.write!(state_path, Jason.encode!(tampered))

      assert {:error, error} =
               WhatsAppAnalytics.load(source_path: @real_source, state_path: state_path)

      assert error.code == "WHATSAPP_AUDIT_EVIDENCE_INVALID"
      assert first.audit.hash_chain == "PASS"
      assert {:ok, %{valid: true, entries: 3}} = ShadowOpsCore.Audit.verify()
    end

    defp configure_audit(path) do
      previous = Application.get_env(:shadowops_core, :audit_path)
      Application.put_env(:shadowops_core, :audit_path, path)

      on_exit(fn -> restore(:audit_path, previous) end)
    end

    defp all_keys(value) when is_map(value),
      do: Map.keys(value) ++ Enum.flat_map(Map.values(value), &all_keys/1)

    defp all_keys(value) when is_list(value), do: Enum.flat_map(value, &all_keys/1)
    defp all_keys(_value), do: []

    defp sha256(value),
      do: :sha256 |> :crypto.hash(value) |> Base.encode16(case: :lower)

    defp restore(key, nil), do: Application.delete_env(:shadowops_core, key)
    defp restore(key, value), do: Application.put_env(:shadowops_core, key, value)
  end

  defp temporary_root(label) do
    root =
      Path.join(
        System.tmp_dir!(),
        "whatsapp-analytics-#{label}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    root
  end
end
