defmodule ShadowOpsCore.AuditCanonicalizationTest do
  use ExUnit.Case, async: false

  alias ShadowOpsCore.Audit

  setup do
    previous = Application.get_env(:shadowops_core, :audit_path)

    path =
      Path.join(
        System.tmp_dir!(),
        "shadowops-audit-canonical-#{System.unique_integer([:positive])}.jsonl"
      )

    Application.put_env(:shadowops_core, :audit_path, path)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:shadowops_core, :audit_path, previous),
        else: Application.delete_env(:shadowops_core, :audit_path)

      File.rm(path)
    end)

    :ok
  end

  test "hash chain survives json round trip when metadata contains atom values" do
    assert {:ok, _} =
             Audit.record(:execution_finished, "operator", "workflow.execute", :success, %{
               executor: :canonical_workflow,
               state: :completed,
               nested: %{mode: :governed}
             })

    assert [%{"metadata" => metadata}] = Audit.list()
    assert metadata["executor"] == "canonical_workflow"
    assert metadata["state"] == "completed"
    assert metadata["nested"]["mode"] == "governed"
    assert {:ok, %{valid: true, entries: 1}} = Audit.verify()
  end
end
