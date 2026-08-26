defmodule ShadowOpsCore.Health.DocumentIntakeTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.Health.DocumentIntake

  test "builds a local-only canonical event from whitelisted metadata" do
    manifest = %{
      resource_id: "health_doc_001",
      document_kind: "coverage_decision",
      document_date: "2026-07-17",
      payer_category: "statutory_health_insurer",
      status: "approved",
      currency: "EUR",
      estimated_total: 7633.00,
      approved_amount: 3185.36,
      evidence_ref: "sha256:example",
      synthetic: true
    }

    assert {:ok, event} =
             DocumentIntake.build_event(manifest, "health.coverage_decision_recorded")

    assert event.source == "health_local"
    assert event.privacy == "local_only"
    assert event.resource_id == "health_doc_001"
    assert event.metadata["approved_amount"] == 3185.36
    refute Map.has_key?(event.metadata, "patient_name")
    refute Map.has_key?(event.metadata, "insurance_number")
  end

  test "drops raw, identifying and free-text fields" do
    metadata =
      DocumentIntake.sanitize_metadata(%{
        resource_id: "health_doc_002",
        document_kind: "invoice",
        patient_name: "DO_NOT_PERSIST",
        insurance_number: "DO_NOT_PERSIST",
        address: "DO_NOT_PERSIST",
        raw: "DO_NOT_PERSIST",
        content: "DO_NOT_PERSIST",
        status: "received"
      })

    assert metadata == %{
             "document_kind" => "invoice",
             "status" => "received"
           }
  end

  test "requires a stable resource identifier" do
    assert {:error, {:missing_field, :resource_id}} =
             DocumentIntake.build_event(%{document_kind: "invoice"})
  end
end
