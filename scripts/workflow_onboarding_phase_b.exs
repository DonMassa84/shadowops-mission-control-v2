defmodule ShadowOpsWorkflowOnboardingPhaseB do
  @moduledoc """
  Deterministic Phase B workflow onboarding proposal generator.

  This script is intentionally non-mutating.

  It:
  - reads config/workflow_registry_v2.yaml
  - enumerates external runtime sets
  - extracts only concrete workflow IDs
  - preserves subset provenance
  - generates canonical IDs
  - detects collisions
  - reports unresolved declared slots
  - writes proposal JSON / Markdown only when --output is supplied

  It does NOT:
  - rewrite workflow_registry_v2.yaml
  - execute workflows
  - start Phoenix intentionally
  - deploy
  - promote 4013
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

    if opts.output do
      write_outputs!(opts.output, report, json)
    end

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
      OptionParser.parse(
        args,
        strict: [
          registry: :string,
          output: :string
        ]
      )

    if invalid != [] do
      raise ArgumentError, "invalid CLI arguments: #{inspect(invalid)}"
    end

    %{
      registry: Keyword.get(opts, :registry, @registry_path),
      output: Keyword.get(opts, :output)
    }
  end

  defp load_registry!(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, registry} when is_map(registry) ->
        registry

      {:error, reason} ->
        raise "registry load failed: #{inspect(reason)}"
    end
  end

  defp build_report(registry) do
    existing_ids = existing_canonical_ids(registry)

    external_sets =
      registry
      |> Map.get("external_runtime_sets", %{})
      |> normalize_sets()

    raw_declared =
      external_sets
      |> Enum.map(& &1["declared_count"])
      |> Enum.sum()

    subset_occurrences =
      external_sets
      |> Enum.filter(& &1["included_in_parent_total"])
      |> Enum.map(& &1["declared_count"])
      |> Enum.sum()

    unique_declared_slots =
      raw_declared - subset_occurrences

    candidates =
      external_sets
      |> Enum.flat_map(&extract_candidates/1)
      |> deduplicate_source_native()
      |> Enum.map(&assign_canonical_id/1)
      |> Enum.sort_by(& &1["canonical_id"])

    concrete_count = length(candidates)

    unresolved_slots =
      max(unique_declared_slots - concrete_count, 0)

    collisions =
      detect_collisions(candidates, existing_ids)

    blockers =
      build_blockers(external_sets, candidates, unresolved_slots, collisions)

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
    |> Enum.map(fn {id, raw} ->
      normalize_set(to_string(id), raw || %{})
    end)
    |> Enum.sort_by(& &1["id"])
  end

  defp normalize_set(id, raw) do
    %{
      "id" => id,
      "runtime" => clean(Map.get(raw, "runtime")),
      "relationship" => clean(Map.get(raw, "relationship")),
      "declared_count" => declared_count(raw),
      "included_in_parent_total" =>
        truthy?(Map.get(raw, "included_in_shadowmaker_tasks_total")),
      "subset_of" => infer_subset(id, raw),
      "workflow_ids" => normalize_workflow_ids(Map.get(raw, "workflow_ids")),
      "risk_groups" => normalize_risk_groups(Map.get(raw, "risk_groups"))
    }
  end

  defp declared_count(raw) do
    raw
    |> then(fn map ->
      Map.get(map, "total_workflow_count") ||
        Map.get(map, "workflow_count") ||
        0
    end)
    |> integer()
  end

  defp infer_subset("whatsapp_agent_pack", raw) do
    if truthy?(Map.get(raw, "included_in_shadowmaker_tasks_total")) do
      "shadowmaker_tasks"
    end
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
            "approval_required" =>
              truthy?(Map.get(group, "approval_required")),
            "lifecycle_state" => "DISCOVERED",
            "executable" => false,
            "evidence_ref" =>
              "config/workflow_registry_v2.yaml##{set["id"]}"
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
          "evidence_ref" =>
            "config/workflow_registry_v2.yaml##{set["id"]}"
        }
      end)

    from_groups ++ from_ids
  end

  defp deduplicate_source_native(candidates) do
    candidates
    |> Enum.group_by(fn wf ->
      {
        wf["source_set"],
        wf["source_native_id"]
      }
    end)
    |> Enum.map(fn {_identity, occurrences} ->
      merge_occurrences!(occurrences)
    end)
  end

  defp merge_occurrences!([candidate]), do: candidate

  defp merge_occurrences!(occurrences) do
    fingerprints =
      occurrences
      |> Enum.map(fn wf ->
        {
          wf["runtime"],
          wf["risk_level"],
          wf["capability"],
          wf["approval_required"]
        }
      end)
      |> Enum.uniq()

    if length(fingerprints) != 1 do
      raise """
      conflicting source-native definition:
      #{inspect(occurrences)}
      """
    end

    hd(occurrences)
  end

  defp assign_canonical_id(wf) do
    canonical =
      @canonical_prefix <>
        slug(wf["source_set"]) <>
        "-" <>
        slug(wf["source_native_id"])

    Map.put(wf, "canonical_id", canonical)
  end

  defp existing_canonical_ids(registry) do
    registry
    |> deep_find_canonical_ids()
    |> MapSet.new()
    |> MapSet.to_list()
  end

  defp deep_find_canonical_ids(term) when is_map(term) do
    own =
      term
      |> Enum.flat_map(fn
        {"canonical_id", value} when is_binary(value) ->
          [value]

        {"id", value}
        when is_binary(value) ->
          if String.starts_with?(value, @canonical_prefix),
            do: [value],
            else: []

        {_key, value} ->
          deep_find_canonical_ids(value)
      end)

    Enum.uniq(own)
  end

  defp deep_find_canonical_ids(term) when is_list(term) do
    Enum.flat_map(term, &deep_find_canonical_ids/1)
  end

  defp deep_find_canonical_ids(_), do: []

  defp detect_collisions(candidates, existing_ids) do
    generated =
      candidates
      |> Enum.map(& &1["canonical_id"])

    internal =
      generated
      |> Enum.frequencies()
      |> Enum.filter(fn {_id, count} -> count > 1 end)
      |> Enum.map(fn {id, count} ->
        %{
          "type" => "generated_duplicate",
          "canonical_id" => id,
          "count" => count
        }
      end)

    existing_set = MapSet.new(existing_ids)

    against_registry =
      generated
      |> Enum.filter(&MapSet.member?(existing_set, &1))
      |> Enum.uniq()
      |> Enum.map(fn id ->
        %{
          "type" => "existing_registry_collision",
          "canonical_id" => id
        }
      end)

    Enum.sort_by(internal ++ against_registry, & &1["canonical_id"])
  end

  defp build_blockers(sets, candidates, unresolved_slots, collisions) do
    set_blockers =
      sets
      |> Enum.flat_map(fn set ->
        concrete =
          Enum.count(candidates, fn wf ->
            wf["source_set"] == set["id"]
          end)

        cond do
          set["declared_count"] > 0 and concrete == 0 ->
            [
              %{
                "type" => "WORKFLOW_IDS_NOT_IMPORTED",
                "source_set" => set["id"],
                "declared_count" => set["declared_count"]
              }
            ]

          true ->
            []
        end
      end)

    runtime_blockers =
      candidates
      |> Enum.filter(&blank?(&1["runtime"]))
      |> Enum.map(fn wf ->
        %{
          "type" => "UNKNOWN_RUNTIME",
          "canonical_id" => wf["canonical_id"]
        }
      end)

    risk_blockers =
      candidates
      |> Enum.filter(fn wf ->
        wf["risk_level"] not in ["L0", "L1", "L2", "L3"]
      end)
      |> Enum.map(fn wf ->
        %{
          "type" => "UNKNOWN_RISK",
          "canonical_id" => wf["canonical_id"]
        }
      end)

    capability_blockers =
      candidates
      |> Enum.filter(&blank?(&1["capability"]))
      |> Enum.map(fn wf ->
        %{
          "type" => "UNKNOWN_CAPABILITY",
          "canonical_id" => wf["canonical_id"]
        }
      end)

    collision_blockers =
      Enum.map(collisions, fn collision ->
        %{
          "type" => "CANONICAL_ID_COLLISION",
          "details" => collision
        }
      end)

    unresolved =
      if unresolved_slots > 0 do
        [
          %{
            "type" => "UNRESOLVED_DECLARED_SLOTS",
            "count" => unresolved_slots
          }
        ]
      else
        []
      end

    (set_blockers ++
       runtime_blockers ++
       risk_blockers ++
       capability_blockers ++
       collision_blockers ++
       unresolved)
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
    expected =
      report["raw_declared_occurrences"] -
        report["subset_occurrences"]

    if expected == report["unique_declared_slots"] do
      errors
    else
      [
        "ARITHMETIC_INVARIANT_FAILED expected=#{expected} actual=#{report["unique_declared_slots"]}"
        | errors
      ]
    end
  end

  defp validate_collisions(errors, report) do
    if report["collisions"] == [] do
      errors
    else
      ["CANONICAL_COLLISION_COUNT=#{length(report["collisions"])}" | errors]
    end
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
    if blank?(wf[key]) do
      ["MISSING_#{String.upcase(key)}=#{inspect(wf)}" | errors]
    else
      errors
    end
  end

  defp validate_l2_l3(errors, wf) do
    if wf["risk_level"] in ["L2", "L3"] and
         wf["approval_required"] != true do
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
    |> Enum.map(fn {key, val} ->
      {key, sort_deep(val)}
    end)
    |> Enum.sort_by(fn {key, _} -> to_string(key) end)
    |> Map.new()
  end

  defp sort_deep(value) when is_list(value) do
    Enum.map(value, &sort_deep/1)
  end

  defp sort_deep(value), do: value

  defp write_outputs!(dir, report, json) do
    File.mkdir_p!(dir)

    json_path =
      Path.join(dir, "external_workflow_proposal.json")

    md_path =
      Path.join(dir, "external_workflow_proposal.md")

    sha_path =
      Path.join(dir, "external_workflow_proposal.sha256")

    File.write!(json_path, json <> "\n")

    digest =
      :crypto.hash(:sha256, json)
      |> Base.encode16(case: :lower)

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
        """
        | `#{wf["canonical_id"]}` | #{wf["source_set"]} | #{wf["risk_level"]} | #{wf["capability"] || "UNKNOWN"} | #{wf["runtime"] || "UNKNOWN"} | #{wf["approval_required"]} |
        """
      end)
      |> Enum.join()

    blocker_rows =
      case report["blockers"] do
        [] ->
          "None.\n"

        blockers ->
          blockers
          |> Enum.map(fn blocker ->
            "- `#{Jason.encode!(blocker)}`\n"
          end)
          |> Enum.join()
      end

    """
    # External Workflow Import Proposal

    This document is generated from the canonical registry source.

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
    digest =
      :crypto.hash(:sha256, json)
      |> Base.encode16(case: :lower)

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

    if normalized in ["L0", "L1", "L2", "L3"] do
      normalized
    else
      "UNKNOWN"
    end
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

  defp clean(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      result -> result
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true

  defp blank?(value) when is_binary(value),
    do: String.trim(value) == ""

  defp blank?(_), do: false

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("TRUE"), do: true
  defp truthy?(1), do: true
  defp truthy?(_), do: false
end

ShadowOpsWorkflowOnboardingPhaseB.main(System.argv())
