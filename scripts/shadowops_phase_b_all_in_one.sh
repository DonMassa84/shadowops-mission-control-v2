#!/usr/bin/env bash
set -euo pipefail

# SHADOWOPS WORKFLOW ONBOARDING — PHASE B PREPROGRAMMED
# Safe boundary: no deploy, no merge, no force push, no registry mutation,
# no 4013/4014 mutation, no destructive L3.

SOURCE_REPO="${SOURCE_REPO:-/tmp/shadowops-4015-current}"
WORKTREE="${WORKTREE:-/tmp/shadowops-kali-workflow-onboarding}"
BRANCH="${BRANCH:-kali/workflow-onboarding-phase-b}"

cd "$SOURCE_REPO"

echo "=== SHADOWOPS PHASE B PREWORK ==="
echo "SOURCE_REPO=$SOURCE_REPO"
echo "SOURCE_HEAD=$(git rev-parse HEAD)"
echo "SOURCE_BRANCH=$(git branch --show-current)"

if [ ! -d "$WORKTREE/.git" ] && [ ! -f "$WORKTREE/.git" ]; then
  rm -rf "$WORKTREE"
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git worktree add "$WORKTREE" "$BRANCH"
  else
    git worktree add -b "$BRANCH" "$WORKTREE" HEAD
  fi
fi

cd "$WORKTREE"

echo "=== WORKTREE ==="
echo "WORKTREE=$WORKTREE"
echo "BRANCH=$(git branch --show-current)"
echo "BASE_SHA=$(git rev-parse HEAD)"

if [ "$(git branch --show-current)" = "local/all-developments" ]; then
  echo "ERROR=SHARED_BRANCH_FORBIDDEN"
  exit 1
fi

mkdir -p scripts test/scripts evidence/workflow_import docs/evidence docs/agent-handoffs

cat > scripts/workflow_onboarding_phase_b.exs <<'ELIXIR'
defmodule ShadowOpsWorkflowOnboardingPhaseB do
  @moduledoc """
  Deterministic Phase B workflow onboarding proposal generator.

  Read-only: reads config/workflow_registry_v2.yaml, enumerates external sets,
  extracts only concrete workflow IDs, preserves subset provenance, generates
  canonical IDs, detects collisions, reports unresolved declared slots, and
  optionally writes proposal evidence.
  """

  @registry_path "config/workflow_registry_v2.yaml"
  @canonical_prefix "so:wf:v1:"

  def main(args) do
    opts = parse_args(args)
    registry = load_registry!(opts.registry)

    report =
      registry
      |> build_report()
      |> validate_report()

    json = canonical_json(report)

    if opts.output, do: write_outputs!(opts.output, report, json)
    print_summary(report, json)

    if report["validation_errors"] == [] do
      IO.puts("PHASE_B_PROPOSAL=PASS")
    else
      Enum.each(report["validation_errors"], &IO.puts("ERROR=#{&1}"))
      IO.puts("PHASE_B_PROPOSAL=FAIL")
      System.halt(1)
    end
  end

  defp parse_args(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args,
        strict: [registry: :string, output: :string]
      )

    if invalid != [], do: raise(ArgumentError, "invalid CLI arguments: #{inspect(invalid)}")

    %{
      registry: Keyword.get(opts, :registry, @registry_path),
      output: Keyword.get(opts, :output)
    }
  end

  defp load_registry!(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, registry} when is_map(registry) -> registry
      {:error, reason} -> raise "registry load failed: #{inspect(reason)}"
    end
  end

  defp build_report(registry) do
    existing_ids = existing_canonical_ids(registry)

    external_sets =
      registry
      |> Map.get("external_runtime_sets", %{})
      |> normalize_sets()

    raw_declared = Enum.sum(Enum.map(external_sets, & &1["declared_count"]))

    subset_occurrences =
      external_sets
      |> Enum.filter(& &1["included_in_parent_total"])
      |> Enum.map(& &1["declared_count"])
      |> Enum.sum()

    unique_declared_slots = raw_declared - subset_occurrences

    candidates =
      external_sets
      |> Enum.flat_map(&extract_candidates/1)
      |> deduplicate_source_native()
      |> Enum.map(&assign_canonical_id/1)
      |> Enum.sort_by(& &1["canonical_id"])

    concrete_count = length(candidates)
    unresolved_slots = max(unique_declared_slots - concrete_count, 0)
    collisions = detect_collisions(candidates, existing_ids)
    blockers = build_blockers(external_sets, candidates, unresolved_slots, collisions)

    %{
      "schema_version" => 1,
      "mode" => "dry_run_proposal",
      "raw_declared_occurrences" => raw_declared,
      "subset_occurrences" => subset_occurrences,
      "proven_duplicate_occurrences" => subset_occurrences,
      "unique_declared_slots" => unique_declared_slots,
      "concrete_definitions" => concrete_count,
      "not_imported_id_slots" => unresolved_slots,
      "existing_canonical_ids" => Enum.sort(existing_ids),
      "external_sets" => external_sets,
      "candidates" => candidates,
      "collisions" => collisions,
      "blockers" => blockers,
      "validation_errors" => []
    }
  end

  defp normalize_sets(sets) when is_map(sets) do
    sets
    |> Enum.map(fn {id, raw} -> normalize_set(to_string(id), raw || %{}) end)
    |> Enum.sort_by(& &1["id"])
  end

  defp normalize_set(id, raw) do
    %{
      "id" => id,
      "runtime" => clean(Map.get(raw, "runtime")),
      "relationship" => clean(Map.get(raw, "relationship")),
      "declared_count" => declared_count(raw),
      "included_in_parent_total" => truthy?(Map.get(raw, "included_in_shadowmaker_tasks_total")),
      "subset_of" => infer_subset(id, raw),
      "workflow_ids" => normalize_workflow_ids(Map.get(raw, "workflow_ids")),
      "risk_groups" => normalize_risk_groups(Map.get(raw, "risk_groups"))
    }
  end

  defp declared_count(raw) do
    (Map.get(raw, "total_workflow_count") || Map.get(raw, "workflow_count") || 0)
    |> integer()
  end

  defp infer_subset("whatsapp_agent_pack", raw) do
    if truthy?(Map.get(raw, "included_in_shadowmaker_tasks_total")), do: "shadowmaker_tasks"
  end

  defp infer_subset(_id, _raw), do: nil

  defp normalize_workflow_ids(nil), do: []
  defp normalize_workflow_ids("not_yet_imported"), do: []

  defp normalize_workflow_ids(ids) when is_list(ids) do
    ids
    |> Enum.map(&to_string/1)
    |> Enum.reject(&blank?/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_workflow_ids(_), do: []
  defp normalize_risk_groups(nil), do: %{}
  defp normalize_risk_groups(groups) when is_map(groups), do: groups
  defp normalize_risk_groups(_), do: %{}

  defp extract_candidates(set) do
    from_groups =
      set["risk_groups"]
      |> Enum.flat_map(fn {risk, group} ->
        group = group || %{}

        workflows =
          group
          |> Map.get("workflows", [])
          |> List.wrap()
          |> Enum.map(&to_string/1)

        Enum.map(workflows, fn workflow_id ->
          %{
            "source_set" => set["id"],
            "source_native_id" => workflow_id,
            "source_kind" => "external_runtime_set",
            "source_ref" => "config/workflow_registry_v2.yaml",
            "relationship" => set["relationship"],
            "subset_of" => set["subset_of"],
            "runtime" => set["runtime"],
            "capability" => clean(Map.get(group, "capability")),
            "risk_level" => normalize_risk(risk),
            "approval_required" => truthy?(Map.get(group, "approval_required")),
            "lifecycle_state" => "DISCOVERED",
            "executable" => false,
            "evidence_ref" => "config/workflow_registry_v2.yaml##{set["id"]}"
          }
        end)
      end)

    from_ids =
      Enum.map(set["workflow_ids"], fn workflow_id ->
        %{
          "source_set" => set["id"],
          "source_native_id" => workflow_id,
          "source_kind" => "external_runtime_set",
          "source_ref" => "config/workflow_registry_v2.yaml",
          "relationship" => set["relationship"],
          "subset_of" => set["subset_of"],
          "runtime" => set["runtime"],
          "capability" => nil,
          "risk_level" => "UNKNOWN",
          "approval_required" => false,
          "lifecycle_state" => "DISCOVERED",
          "executable" => false,
          "evidence_ref" => "config/workflow_registry_v2.yaml##{set["id"]}"
        }
      end)

    from_groups ++ from_ids
  end

  defp deduplicate_source_native(candidates) do
    candidates
    |> Enum.group_by(fn wf -> {wf["source_set"], wf["source_native_id"]} end)
    |> Enum.map(fn {_identity, occurrences} -> merge_occurrences!(occurrences) end)
  end

  defp merge_occurrences!([candidate]), do: candidate

  defp merge_occurrences!(occurrences) do
    fingerprints =
      occurrences
      |> Enum.map(fn wf ->
        {wf["runtime"], wf["risk_level"], wf["capability"], wf["approval_required"]}
      end)
      |> Enum.uniq()

    if length(fingerprints) != 1 do
      raise "conflicting source-native definition: #{inspect(occurrences)}"
    end

    hd(occurrences)
  end

  defp assign_canonical_id(wf) do
    canonical = @canonical_prefix <> slug(wf["source_set"]) <> "-" <> slug(wf["source_native_id"])
    Map.put(wf, "canonical_id", canonical)
  end

  defp existing_canonical_ids(registry) do
    registry
    |> deep_find_canonical_ids()
    |> MapSet.new()
    |> MapSet.to_list()
  end

  defp deep_find_canonical_ids(term) when is_map(term) do
    term
    |> Enum.flat_map(fn
      {"canonical_id", value} when is_binary(value) -> [value]
      {"id", value} when is_binary(value) -> if String.starts_with?(value, @canonical_prefix), do: [value], else: []
      {_key, value} -> deep_find_canonical_ids(value)
    end)
    |> Enum.uniq()
  end

  defp deep_find_canonical_ids(term) when is_list(term), do: Enum.flat_map(term, &deep_find_canonical_ids/1)
  defp deep_find_canonical_ids(_), do: []

  defp detect_collisions(candidates, existing_ids) do
    generated = Enum.map(candidates, & &1["canonical_id"])

    internal =
      generated
      |> Enum.frequencies()
      |> Enum.filter(fn {_id, count} -> count > 1 end)
      |> Enum.map(fn {id, count} ->
        %{"type" => "generated_duplicate", "canonical_id" => id, "count" => count}
      end)

    existing_set = MapSet.new(existing_ids)

    against_registry =
      generated
      |> Enum.filter(&MapSet.member?(existing_set, &1))
      |> Enum.uniq()
      |> Enum.map(fn id ->
        %{"type" => "existing_registry_collision", "canonical_id" => id}
      end)

    Enum.sort_by(internal ++ against_registry, & &1["canonical_id"])
  end

  defp build_blockers(sets, candidates, unresolved_slots, collisions) do
    set_blockers =
      Enum.flat_map(sets, fn set ->
        concrete = Enum.count(candidates, fn wf -> wf["source_set"] == set["id"] end)

        if set["declared_count"] > 0 and concrete == 0 do
          [%{"type" => "WORKFLOW_IDS_NOT_IMPORTED", "source_set" => set["id"], "declared_count" => set["declared_count"]}]
        else
          []
        end
      end)

    runtime_blockers =
      candidates
      |> Enum.filter(&blank?(&1["runtime"]))
      |> Enum.map(fn wf -> %{"type" => "UNKNOWN_RUNTIME", "canonical_id" => wf["canonical_id"]} end)

    risk_blockers =
      candidates
      |> Enum.filter(fn wf -> wf["risk_level"] not in ["L0", "L1", "L2", "L3"] end)
      |> Enum.map(fn wf -> %{"type" => "UNKNOWN_RISK", "canonical_id" => wf["canonical_id"]} end)

    capability_blockers =
      candidates
      |> Enum.filter(&blank?(&1["capability"]))
      |> Enum.map(fn wf -> %{"type" => "UNKNOWN_CAPABILITY", "canonical_id" => wf["canonical_id"]} end)

    collision_blockers =
      Enum.map(collisions, fn collision -> %{"type" => "CANONICAL_ID_COLLISION", "details" => collision} end)

    unresolved = if unresolved_slots > 0, do: [%{"type" => "UNRESOLVED_DECLARED_SLOTS", "count" => unresolved_slots}], else: []

    (set_blockers ++ runtime_blockers ++ risk_blockers ++ capability_blockers ++ collision_blockers ++ unresolved)
    |> Enum.sort_by(&:erlang.term_to_binary/1)
  end

  defp validate_report(report) do
    errors =
      []
      |> validate_arithmetic(report)
      |> validate_collisions(report)
      |> validate_candidate_contract(report)
      |> Enum.uniq()
      |> Enum.sort()

    Map.put(report, "validation_errors", errors)
  end

  defp validate_arithmetic(errors, report) do
    expected = report["raw_declared_occurrences"] - report["subset_occurrences"]

    if expected == report["unique_declared_slots"] do
      errors
    else
      ["ARITHMETIC_INVARIANT_FAILED expected=#{expected} actual=#{report["unique_declared_slots"]}" | errors]
    end
  end

  defp validate_collisions(errors, report) do
    if report["collisions"] == [], do: errors, else: ["CANONICAL_COLLISION_COUNT=#{length(report["collisions"])}" | errors]
  end

  defp validate_candidate_contract(errors, report) do
    Enum.reduce(report["candidates"], errors, fn wf, acc ->
      acc
      |> require_field(wf, "canonical_id")
      |> require_field(wf, "source_set")
      |> require_field(wf, "source_native_id")
      |> require_field(wf, "source_ref")
      |> require_field(wf, "evidence_ref")
      |> validate_l2_l3(wf)
    end)
  end

  defp require_field(errors, wf, key) do
    if blank?(wf[key]), do: ["MISSING_#{String.upcase(key)}=#{inspect(wf)}" | errors], else: errors
  end

  defp validate_l2_l3(errors, wf) do
    if wf["risk_level"] in ["L2", "L3"] and wf["approval_required"] != true do
      ["UNAPPROVED_L2_L3=#{wf["canonical_id"]}" | errors]
    else
      errors
    end
  end

  defp canonical_json(report) do
    report
    |> sort_deep()
    |> Jason.encode!(pretty: true)
  end

  defp sort_deep(value) when is_map(value) do
    value
    |> Enum.map(fn {key, val} -> {key, sort_deep(val)} end)
    |> Enum.sort_by(fn {key, _} -> to_string(key) end)
    |> Map.new()
  end

  defp sort_deep(value) when is_list(value), do: Enum.map(value, &sort_deep/1)
  defp sort_deep(value), do: value

  defp write_outputs!(dir, report, json) do
    File.mkdir_p!(dir)
    json_path = Path.join(dir, "external_workflow_proposal.json")
    md_path = Path.join(dir, "external_workflow_proposal.md")
    sha_path = Path.join(dir, "external_workflow_proposal.sha256")

    File.write!(json_path, json <> "\n")
    digest = :crypto.hash(:sha256, json) |> Base.encode16(case: :lower)
    File.write!(sha_path, "#{digest}  external_workflow_proposal.json\n")
    File.write!(md_path, markdown(report, digest))

    IO.puts("PROPOSAL_JSON=#{json_path}")
    IO.puts("PROPOSAL_MD=#{md_path}")
    IO.puts("PROPOSAL_SHA256=#{digest}")
  end

  defp markdown(report, digest) do
    candidate_rows =
      report["candidates"]
      |> Enum.map(fn wf ->
        "| `#{wf["canonical_id"]}` | #{wf["source_set"]} | #{wf["risk_level"]} | #{wf["capability"] || "UNKNOWN"} | #{wf["runtime"] || "UNKNOWN"} | #{wf["approval_required"]} |\n"
      end)
      |> Enum.join()

    blocker_rows =
      case report["blockers"] do
        [] -> "None.\n"
        blockers -> Enum.map_join(blockers, fn blocker -> "- `#{Jason.encode!(blocker)}`\n" end)
      end

    """
    # External Workflow Import Proposal

    **Mode:** dry-run proposal  
    **Registry mutation:** NO  
    **Runtime execution:** NO  
    **Proposal SHA256:** `#{digest}`

    ## Accounting

    | Metric | Count |
    |---|---:|
    | Raw declared occurrences | #{report["raw_declared_occurrences"]} |
    | Subset occurrences | #{report["subset_occurrences"]} |
    | Proven duplicate occurrences | #{report["proven_duplicate_occurrences"]} |
    | Unique declared slots | #{report["unique_declared_slots"]} |
    | Concrete definitions | #{report["concrete_definitions"]} |
    | Not imported ID slots | #{report["not_imported_id_slots"]} |
    | Canonical collisions | #{length(report["collisions"])} |
    | Validation errors | #{length(report["validation_errors"])} |

    ## Concrete candidates

    | Canonical ID | Source | Risk | Capability | Runtime | Approval |
    |---|---|---|---|---|---|
    #{candidate_rows}

    ## Blockers

    #{blocker_rows}

    ## Safety

    - Registry mutation: NO
    - Runtime execution: NO
    - 4013 promotion: NO
    - 4014 mutation: NO
    - Deploy: NO
    - Force push: NO
    """
  end

  defp print_summary(report, json) do
    digest = :crypto.hash(:sha256, json) |> Base.encode16(case: :lower)

    IO.puts("RAW_DECLARED_OCCURRENCES=#{report["raw_declared_occurrences"]}")
    IO.puts("SUBSET_OCCURRENCES=#{report["subset_occurrences"]}")
    IO.puts("PROVEN_DUPLICATE_OCCURRENCES=#{report["proven_duplicate_occurrences"]}")
    IO.puts("UNIQUE_DECLARED_SLOTS=#{report["unique_declared_slots"]}")
    IO.puts("CONCRETE_DEFINITIONS=#{report["concrete_definitions"]}")
    IO.puts("NOT_IMPORTED_ID_SLOTS=#{report["not_imported_id_slots"]}")
    IO.puts("CANONICAL_COLLISIONS=#{length(report["collisions"])}")
    IO.puts("BLOCKERS=#{length(report["blockers"])}")
    IO.puts("VALIDATION_ERRORS=#{length(report["validation_errors"])}")
    IO.puts("PROPOSAL_SHA256=#{digest}")
    IO.puts("REGISTRY_MUTATION=NO")
    IO.puts("RUNTIME_EXECUTION=NO")
    IO.puts("4013_MUTATION=NO")
    IO.puts("4014_MUTATION=NO")
  end

  defp slug(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace("_", "-")
    |> String.replace(~r/[^a-z0-9-]+/u, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

  defp normalize_risk(value) do
    normalized = to_string(value)
    if normalized in ["L0", "L1", "L2", "L3"], do: normalized, else: "UNKNOWN"
  end

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> 0
    end
  end

  defp integer(_), do: 0
  defp clean(nil), do: nil
  defp clean(value), do: value |> to_string() |> String.trim() |> case do "" -> nil; result -> result end
  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false
  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("TRUE"), do: true
  defp truthy?(1), do: true
  defp truthy?(_), do: false
end

ShadowOpsWorkflowOnboardingPhaseB.main(System.argv())
ELIXIR

cat > test/scripts/workflow_onboarding_phase_b_contract_test.exs <<'ELIXIR'
defmodule WorkflowOnboardingPhaseBContractTest do
  use ExUnit.Case, async: true

  @script "scripts/workflow_onboarding_phase_b.exs"

  test "phase B implementation exists", do: assert(File.regular?(@script))

  test "contains no registry writer" do
    body = File.read!(@script)
    refute body =~ "YamlElixir.write_to_file"
    refute body =~ "YamlElixir.write_to_string"
    refute body =~ ~s(File.write!("config/workflow_registry_v2.yaml")
  end

  test "does not execute workflows" do
    body = File.read!(@script)
    assert body =~ "RUNTIME_EXECUTION=NO"
    refute body =~ "System.cmd("
    refute body =~ "Port.open("
  end

  test "does not invent external IDs" do
    body = File.read!(@script)
    refute body =~ "opencode_standard-1"
    refute body =~ "telegram_workflow_controller-1"
  end

  test "preserves WhatsApp subset provenance" do
    body = File.read!(@script)
    assert body =~ "whatsapp_agent_pack"
    assert body =~ "shadowmaker_tasks"
    assert body =~ "subset_of"
  end

  test "has canonical collision gate", do: assert(File.read!(@script) =~ "CANONICAL_ID_COLLISION")
  test "has L2/L3 approval gate", do: assert(File.read!(@script) =~ "UNAPPROVED_L2_L3")
  test "has unresolved workflow blocker", do: assert(File.read!(@script) =~ "WORKFLOW_IDS_NOT_IMPORTED")
  test "has unknown runtime blocker", do: assert(File.read!(@script) =~ "UNKNOWN_RUNTIME")
  test "has unknown capability blocker", do: assert(File.read!(@script) =~ "UNKNOWN_CAPABILITY")
  test "has unknown risk blocker", do: assert(File.read!(@script) =~ "UNKNOWN_RISK")

  test "has deterministic SHA evidence" do
    body = File.read!(@script)
    assert body =~ ":crypto.hash(:sha256"
    assert body =~ "PROPOSAL_SHA256"
  end
end
ELIXIR

cat > scripts/safe_test_gate.sh <<'SAFE'
#!/usr/bin/env bash
set -euo pipefail
PORT=4013
listener() { ss -ltnp 2>/dev/null | grep ":${PORT} " || true; }
BEFORE="$(listener)"
printf '%s\n' "=== 4013 BEFORE ===" "$BEFORE"
BEFORE_PID="$(printf '%s\n' "$BEFORE" | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | head -1)"
set +e
MIX_ENV=test mix test
TEST_RC=$?
set -e
AFTER="$(listener)"
printf '%s\n' "=== 4013 AFTER ===" "$AFTER"
AFTER_PID="$(printf '%s\n' "$AFTER" | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | head -1)"
TEST_STARTED_4013_LISTENER=NO
if [ -z "$BEFORE_PID" ] && [ -n "$AFTER_PID" ]; then TEST_STARTED_4013_LISTENER=YES; fi
if [ -n "$BEFORE_PID" ] && [ -n "$AFTER_PID" ] && [ "$BEFORE_PID" != "$AFTER_PID" ]; then TEST_STARTED_4013_LISTENER=YES; fi
echo "TEST_RC=$TEST_RC"
echo "PORT_4013_BEFORE_PID=${BEFORE_PID:-NONE}"
echo "PORT_4013_AFTER_PID=${AFTER_PID:-NONE}"
echo "TEST_STARTED_4013_LISTENER=$TEST_STARTED_4013_LISTENER"
[ "$TEST_RC" -eq 0 ] || exit "$TEST_RC"
[ "$TEST_STARTED_4013_LISTENER" = "NO" ] || { echo "SAFETY_GATE=FAIL"; exit 91; }
echo "SAFETY_GATE=PASS"
SAFE
chmod +x scripts/safe_test_gate.sh

cat > scripts/run_workflow_onboarding_phase_b.sh <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
OUT="evidence/workflow_import"
mkdir -p "$OUT"
mix format scripts/workflow_onboarding_phase_b.exs test/scripts/workflow_onboarding_phase_b_contract_test.exs
MIX_ENV=test mix compile --warnings-as-errors
mix run --no-start scripts/workflow_onboarding_phase_b.exs --output "$OUT" | tee "$OUT/phase_b_run.txt"
sha256sum "$OUT/external_workflow_proposal.json" "$OUT/external_workflow_proposal.md" "$OUT/phase_b_run.txt" > "$OUT/SHA256SUMS"
cat "$OUT/SHA256SUMS"
MIX_ENV=test mix test test/scripts/workflow_onboarding_phase_b_contract_test.exs
echo "PHASE_B_RUNNER=PASS"
RUNNER
chmod +x scripts/run_workflow_onboarding_phase_b.sh

cat > scripts/workflow_registry_apply_phase_c.sh <<'PHASEC'
#!/usr/bin/env bash
set -euo pipefail
echo "PHASE_C=BLOCKED_BY_DESIGN"
echo "REASON=REGISTRY_APPLY_REQUIRES_REVIEWED_PROPOSAL_AND_EXACT_SHA"
echo "REGISTRY_MUTATION=NO"
exit 2
PHASEC
chmod +x scripts/workflow_registry_apply_phase_c.sh

cat > scripts/workflow_l2_execution_gate.sh <<'L2'
#!/usr/bin/env bash
set -euo pipefail
echo "L2_EXECUTION=BLOCKED_BY_DEFAULT"
echo "APPROVAL_REQUIRED=YES"
echo "SINGLE_USE_APPROVAL_REQUIRED=YES"
exit 2
L2
chmod +x scripts/workflow_l2_execution_gate.sh

cat > scripts/workflow_l3_execution_gate.sh <<'L3'
#!/usr/bin/env bash
set -euo pipefail
echo "L3_EXECUTION=BLOCKED"
echo "EXPLICIT_AUTHORIZATION_REQUIRED=YES"
exit 2
L3
chmod +x scripts/workflow_l3_execution_gate.sh

cat > docs/agent-handoffs/NEXT_SESSION_MEMO.md <<'MEMO'
# ShadowOps Next Session Memo

## Candidate
- Worker: Kali
- Scope: Workflow onboarding / census / import proposal
- Production mutation: prohibited
- 4013 promotion: prohibited

## Remaining
1. Resolve unidentified external workflow IDs with provenance.
2. Review Phase B proposal.
3. Implement Phase C registry application only after proposal review.
4. Bind capabilities and executors.
5. Run bounded L0/L1 validation.
6. Validate L2 approval path.
7. Keep L3 blocked.
8. Freeze candidate.
9. MiMo audit.
10. Hy3 audit.
11. 4015 acceptance.
12. Stop before 4013.

## First command
```bash
bash scripts/run_workflow_onboarding_phase_b.sh
```
MEMO

mix format scripts/workflow_onboarding_phase_b.exs test/scripts/workflow_onboarding_phase_b_contract_test.exs
MIX_ENV=test mix compile --warnings-as-errors
set +e
bash scripts/run_workflow_onboarding_phase_b.sh
PHASE_B_RC=$?
set -e

echo "PHASE_B_RC=$PHASE_B_RC"
echo "REGISTRY_MUTATION=NO"
echo "RUNTIME_EXECUTION=NO"
echo "L2_REAL_EXECUTION=NO"
echo "L3_REAL_EXECUTION=NO"
echo "4013_MUTATION=NO"
echo "4014_MUTATION=NO"
echo "DEPLOY=NO"
echo "MERGE=NO"
echo "FORCE_PUSH=NO"

[ "$PHASE_B_RC" -eq 0 ] || { echo "FINAL_STATUS=BLOCKED"; exit 1; }

git status --short
git add \
  scripts/workflow_onboarding_phase_b.exs \
  scripts/run_workflow_onboarding_phase_b.sh \
  scripts/safe_test_gate.sh \
  scripts/workflow_registry_apply_phase_c.sh \
  scripts/workflow_l2_execution_gate.sh \
  scripts/workflow_l3_execution_gate.sh \
  test/scripts/workflow_onboarding_phase_b_contract_test.exs \
  evidence/workflow_import \
  docs/agent-handoffs/NEXT_SESSION_MEMO.md

if git diff --cached --quiet; then
  echo "COMMIT=NO_CHANGES"
else
  git commit -m "feat: prepare governed workflow onboarding phase B"
fi

git push -u origin "$BRANCH"
LOCAL_HEAD="$(git rev-parse HEAD)"
REMOTE_HEAD="$(git rev-parse "origin/$BRANCH")"
echo "WORKER=KALI"
echo "BRANCH=$BRANCH"
echo "VERSIONED=YES"
echo "PUSHED=YES"
echo "LOCAL_HEAD=$LOCAL_HEAD"
echo "REMOTE_HEAD=$REMOTE_HEAD"
[ "$LOCAL_HEAD" = "$REMOTE_HEAD" ] || { echo "REMOTE_HEAD_MATCH=NO"; exit 1; }
echo "LOCAL_HEAD=REMOTE_HEAD"
echo "REGISTRY_MUTATION=NO"
echo "RUNTIME_EXECUTION=NO"
echo "4013_MUTATION=NO"
echo "4014_MUTATION=NO"
echo "DEPLOY=NO"
echo "MERGE=NO"
echo "FORCE_PUSH=NO"
echo "FINAL_STATUS=PASS"
