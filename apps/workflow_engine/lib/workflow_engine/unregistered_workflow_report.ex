defmodule WorkflowEngine.UnregisteredWorkflowReport do
  @moduledoc """
  Accounts for local workflow discovery evidence without granting execution rights.

  The report projects `LocalWorkflowRegistry` identities onto the canonical workflow
  registry. Exact source references are required; unknown or ambiguous mappings fail closed.
  """

  alias ShadowOpsCore.{CapabilityRegistry, LocalWorkflowRegistry, WorkflowCuration}
  alias WorkflowEngine.{Registry, WorkflowIds}

  @classifications ~w(READY_EXECUTABLE CONNECTED_NOT_E2E READ_EVIDENCE_ONLY REGISTRY_ONLY MOCK_ONLY BLOCKED)
  @local_states ~w(LOCALWF_UNMAPPED CANONICAL_REGISTERED)

  def build(home \\ nil, canonical_entries \\ nil) do
    root = Path.expand(home || System.user_home!())
    inventory = LocalWorkflowRegistry.inventory(root)
    registry = LocalWorkflowRegistry.snapshot(root)
    curated = WorkflowCuration.snapshot(registry)
    canonical_entries = canonical_entries || canonical_entries(root)

    curated_by_id = Map.new(curated.records, &{&1.id, &1})
    mappings = Enum.group_by(canonical_entries, & &1.source_ref)

    records =
      Enum.map(inventory.records, fn raw ->
        project(raw, Map.get(curated_by_id, raw.expected_local_id), mappings)
      end)

    metrics = metrics(inventory, registry, canonical_entries, records)
    invariants = invariants(records, metrics)

    %{
      schema_version: 1,
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      source_report_ref: inventory.report_ref,
      metrics: metrics,
      invariants: invariants,
      records: records
    }
  end

  def write(report, path) when is_map(report) and is_binary(path) do
    File.mkdir_p!(Path.dirname(path))
    File.write(path, Jason.encode_to_iodata!(report, pretty: true))
  end

  defp canonical_entries(root) do
    with {:ok, registry} <- Registry.load(),
         {:ok, ids} <- WorkflowIds.load() do
      canonical =
        ids["canonical_workflows"]
        |> Enum.flat_map(fn {key, identity} ->
          workflow = get_in(registry, ["workflows", key]) || %{}
          contract = get_in(registry, ["agent_contracts", key]) || %{}

          workflow
          |> workflow_refs()
          |> Enum.map(fn ref ->
            canonical_entry(identity["id"], identity["domain"], ref, workflow, contract, root)
          end)
        end)

      federation =
        ids["federation_workflows"]
        |> Enum.map(fn {_key, identity} ->
          %{
            id: identity["id"],
            domain: identity["domain"],
            source_ref: normalize_ref(identity["source_definition"], root),
            capability: nil,
            risk: nil,
            approval_required: nil,
            adapter: nil,
            audit_required: false
          }
        end)

      Enum.reject(canonical ++ federation, &is_nil(&1.source_ref))
    else
      _ -> []
    end
  end

  defp workflow_refs(workflow) do
    [workflow["definition"], workflow["runtime"] | List.wrap(workflow["source_components"])]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp canonical_entry(id, domain, ref, workflow, contract, root) do
    capability = contract["capabilities"] |> List.wrap() |> List.first()
    risk = get_in(contract, ["agent_spec", "risk_level"])

    %{
      id: id,
      domain: domain,
      source_ref: normalize_ref(ref, root),
      capability: capability,
      risk: risk,
      approval_required: get_in(contract, ["agent_spec", "approval_required"]),
      adapter: adapter(workflow),
      audit_required: get_in(contract, ["evidence_policy", "audit_required"]) == true
    }
  end

  defp normalize_ref(ref, root) when is_binary(ref) do
    if Path.type(ref) == :absolute do
      expanded = Path.expand(ref)
      if inside_root?(expanded, root), do: Path.relative_to(expanded, root)
    else
      ref
    end
  end

  defp normalize_ref(_, _), do: nil

  defp adapter(%{"runtime" => "github_actions"}), do: "GitHubActionsAdapter"

  defp adapter(workflow) do
    runtime = workflow["runtime"] || workflow["target_runtime"]
    definition = workflow["definition"] || ""

    cond do
      String.ends_with?(definition, ".service") -> "SystemdAdapter"
      is_binary(runtime) and Path.type(runtime) == :absolute -> "ScriptAdapter"
      true -> nil
    end
  end

  defp project(%{registration_state: "LOCALWF_REGISTERED"} = raw, curated, mappings) do
    matches = Map.get(mappings, raw.source_ref, [])
    canonical = if(length(matches) == 1, do: hd(matches))
    ambiguous = length(matches) > 1
    runtime_verified = curated.runtime_verified == true
    tested = curated.execution_tested == true
    governance_mapped = not is_nil(canonical) and canonical_governed?(canonical)

    executable =
      curated.executable == true and runtime_verified and tested and governance_mapped and
        canonical.audit_required == true

    classification =
      cond do
        executable -> "READY_EXECUTABLE"
        runtime_verified -> "CONNECTED_NOT_E2E"
        true -> "READ_EVIDENCE_ONLY"
      end

    registration_state =
      if canonical && not ambiguous, do: "CANONICAL_REGISTERED", else: "LOCALWF_UNMAPPED"

    raw
    |> base_record()
    |> Map.merge(%{
      purpose: curated.purpose,
      domain: if(canonical, do: canonical.domain, else: curated.category),
      registration_state: registration_state,
      classification: classification,
      real_source: curated.real_source_state == "DISCOVERED_REAL_ARTIFACT" or runtime_verified,
      synthetic: false,
      runtime_verified: runtime_verified,
      governance_mapped: governance_mapped,
      tested: tested,
      executable: executable,
      canonical_workflow_id: canonical && canonical.id,
      capability: canonical && canonical.capability,
      risk: canonical && canonical.risk,
      approval_required: canonical && canonical.approval_required,
      adapter: canonical && canonical.adapter,
      audited: canonical && canonical.audit_required,
      blocker: blocker(ambiguous, canonical, runtime_verified, tested, governance_mapped),
      evidence_refs: curated.evidence_refs
    })
  end

  defp project(raw, _curated, _mappings) do
    raw
    |> base_record()
    |> Map.merge(%{
      purpose: nil,
      domain: nil,
      registration_state: raw.registration_state,
      classification: "BLOCKED",
      real_source: false,
      synthetic: false,
      runtime_verified: false,
      governance_mapped: false,
      tested: false,
      executable: false,
      canonical_workflow_id: nil,
      capability: nil,
      risk: nil,
      approval_required: nil,
      adapter: nil,
      audited: false,
      blocker: raw.rejection_reason,
      evidence_refs: []
    })
  end

  defp base_record(raw) do
    Map.take(raw, [
      :workflow_identity,
      :source,
      :source_ref,
      :type,
      :file_exists,
      :regular_file,
      :inside_allowed_root,
      :excluded_path,
      :expected_local_id,
      :rejection_reason
    ])
  end

  defp canonical_governed?(canonical) do
    capability_known?(canonical.capability) and canonical.risk in ~w(L0 L1 L2 L3) and
      is_boolean(canonical.approval_required) and
      (canonical.risk not in ~w(L2 L3) or canonical.approval_required == true)
  end

  defp capability_known?(nil), do: false
  defp capability_known?(capability), do: match?({:ok, _}, CapabilityRegistry.lookup(capability))

  defp blocker(true, _canonical, _runtime, _tested, _governance),
    do: "AMBIGUOUS_CANONICAL_MAPPING"

  defp blocker(false, nil, _runtime, _tested, _governance),
    do: "CANONICAL_MAPPING_NOT_PROVEN"

  defp blocker(false, _canonical, false, _tested, _governance), do: "RUNTIME_NOT_VERIFIED"
  defp blocker(false, _canonical, true, false, _governance), do: "E2E_NOT_TESTED"
  defp blocker(false, _canonical, true, true, false), do: "GOVERNANCE_INCOMPLETE"
  defp blocker(false, _canonical, true, true, true), do: nil

  defp metrics(inventory, registry, canonical_entries, records) do
    frequencies = Enum.frequencies_by(records, & &1.classification)

    %{
      raw_discovered_total: inventory.counts.raw_discovered_total,
      localwf_registered_total: registry.counts.registered,
      raw_eligible_registered: inventory.counts.raw_eligible_registered,
      raw_eligible_unregistered: inventory.counts.raw_eligible_unregistered,
      raw_rejected_policy: inventory.counts.raw_rejected_policy,
      raw_duplicates: inventory.counts.raw_duplicates,
      raw_unknown: inventory.counts.raw_unknown,
      canonical_workflow_total: canonical_entries |> Enum.map(& &1.id) |> Enum.uniq() |> length(),
      localwf_unmapped_total: Enum.count(records, &(&1.registration_state == "LOCALWF_UNMAPPED")),
      new_local_identities: 0,
      new_canonical_mappings: 0,
      ready_executable: Map.get(frequencies, "READY_EXECUTABLE", 0),
      connected_not_e2e: Map.get(frequencies, "CONNECTED_NOT_E2E", 0),
      read_evidence_only: Map.get(frequencies, "READ_EVIDENCE_ONLY", 0),
      registry_only: Map.get(frequencies, "REGISTRY_ONLY", 0),
      mock_only: Map.get(frequencies, "MOCK_ONLY", 0),
      blocked: Map.get(frequencies, "BLOCKED", 0),
      real_source_proven: Enum.count(records, & &1.real_source),
      runtime_verified: Enum.count(records, & &1.runtime_verified),
      governance_mapped: Enum.count(records, & &1.governance_mapped),
      tested: Enum.count(records, & &1.tested),
      e2e_verified: Enum.count(records, &(&1.tested and &1.runtime_verified)),
      synthetic_ready_count:
        Enum.count(records, &(&1.classification == "READY_EXECUTABLE" and &1.synthetic)),
      mock_ready_count:
        Enum.count(
          records,
          &(&1.classification == "READY_EXECUTABLE" and &1.classification == "MOCK_ONLY")
        ),
      unknown_runtime_ready_count:
        Enum.count(
          records,
          &(&1.classification == "READY_EXECUTABLE" and not &1.runtime_verified)
        ),
      unapproved_mutation_count:
        Enum.count(records, fn row ->
          row.executable and row.risk in ~w(L2 L3) and row.approval_required != true
        end),
      arbitrary_command_path_count:
        Enum.count(records, &(&1.executable and &1.adapter in [nil, "ARBITRARY_COMMAND"])),
      arbitrary_systemd_unit_count:
        Enum.count(records, &(&1.executable and &1.adapter == "ARBITRARY_SYSTEMD_UNIT"))
    }
  end

  defp invariants(records, metrics) do
    accounted =
      metrics.raw_eligible_registered + metrics.raw_eligible_unregistered +
        metrics.raw_rejected_policy + metrics.raw_duplicates + metrics.raw_unknown

    localwf = Enum.filter(records, &(&1.registration_state in @local_states))
    executables = Enum.filter(records, & &1.executable)

    %{
      all_raw_candidates_accounted_for: accounted == metrics.raw_discovered_total,
      all_localwf_ids_unique:
        localwf |> Enum.map(& &1.workflow_identity) |> then(&(&1 == Enum.uniq(&1))),
      all_localwf_records_classified:
        Enum.all?(localwf, &(&1.classification in @classifications)),
      no_duplicate_canonical_id:
        records
        |> Enum.reject(&is_nil(&1.canonical_workflow_id))
        |> Enum.group_by(& &1.workflow_identity)
        |> Enum.all?(fn {_id, rows} ->
          rows |> Enum.map(& &1.canonical_workflow_id) |> Enum.uniq() |> length() == 1
        end),
      no_synthetic_ready: metrics.synthetic_ready_count == 0,
      no_mock_ready: metrics.mock_ready_count == 0,
      no_unknown_runtime_ready: metrics.unknown_runtime_ready_count == 0,
      no_arbitrary_command_path: metrics.arbitrary_command_path_count == 0,
      no_arbitrary_systemd_unit: metrics.arbitrary_systemd_unit_count == 0,
      all_executables_have_real_source: Enum.all?(executables, & &1.real_source),
      all_executables_have_runtime: Enum.all?(executables, & &1.runtime_verified),
      all_executables_have_capability: Enum.all?(executables, &capability_known?(&1.capability)),
      all_executables_have_risk: Enum.all?(executables, &(&1.risk in ~w(L0 L1 L2 L3))),
      all_executables_audited: Enum.all?(executables, &(&1.audited == true)),
      all_l2_l3_require_approval:
        Enum.all?(executables, &(&1.risk not in ~w(L2 L3) or &1.approval_required == true)),
      single_use_approval_enforced: approval_single_use?()
    }
  end

  defp approval_single_use? do
    function_exported?(ShadowOpsCore.ApprovalStore, :consume, 5)
  end

  defp inside_root?(path, root), do: path == root or String.starts_with?(path, root <> "/")
end
