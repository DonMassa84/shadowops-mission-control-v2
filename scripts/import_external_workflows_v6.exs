#!/usr/bin/env elixir

defmodule ImportExternalWorkflows do
  @moduledoc """
  Deterministic, read-only external workflow census/import proposal.

  Phase A only:
  - reads registry
  - derives declared workflow slots
  - extracts only concrete proven workflow IDs
  - preserves explicit subset semantics
  - creates deterministic canonical proposal
  - validates provenance/runtime/risk/capability
  - never writes the registry
  - never starts Phoenix
  """

  @registry_path "config/workflow_registry_v2.yaml"
  @canonical_prefix "so:wf:v1:"

  def main(args) do
    opts = parse_args(args)

    IO.puts("=== SHADOWOPS EXTERNAL WORKFLOW IMPORTER V6 ===")
    IO.puts("MODE=DRY_RUN")
    IO.puts("REGISTRY=#{opts.registry}")
    IO.puts("")

    registry = load_registry!(opts.registry)

    report =
      registry
      |> build_report()
      |> validate_report()

    print_report(report)

    if report.validation_errors == [] do
      IO.puts("DRY_RUN=PASS")
      :ok
    else
      IO.puts("DRY_RUN=FAIL")
      Enum.each(report.validation_errors, fn error ->
        IO.puts("ERROR=#{error}")
      end)

      System.halt(1)
    end
  end

  # ---------------------------------------------------------------------------
  # CLI
  # ---------------------------------------------------------------------------

  defp parse_args(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args,
        strict: [
          registry: :string
        ]
      )

    if invalid != [] do
      raise ArgumentError, "invalid arguments: #{inspect(invalid)}"
    end

    %{
      registry: Keyword.get(opts, :registry, @registry_path)
    }
  end

  # ---------------------------------------------------------------------------
  # Registry loading
  # ---------------------------------------------------------------------------

  defp load_registry!(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, registry} when is_map(registry) ->
        registry

      registry when is_map(registry) ->
        registry

      {:error, reason} ->
        raise "registry load failed: #{inspect(reason)}"

      other ->
        raise "unexpected registry loader result: #{inspect(other)}"
    end
  end

  # ---------------------------------------------------------------------------
  # Report
  # ---------------------------------------------------------------------------

  defp build_report(registry) do
    external_sets =
      registry
      |> Map.get("external_runtime_sets", %{})
      |> normalize_external_sets()

    candidates =
      external_sets
      |> Enum.flat_map(&extract_concrete_candidates/1)
      |> Enum.sort_by(&candidate_sort_key/1)

    canonical_candidates =
      candidates
      |> assign_canonical_ids()
      |> Enum.sort_by(& &1["canonical_id"])

    raw_declared_occurrences =
      external_sets
      |> Enum.map(& &1.declared_count)
      |> Enum.sum()

    subset_declared_occurrences =
      external_sets
      |> Enum.filter(& &1.included_in_parent_total)
      |> Enum.map(& &1.declared_count)
      |> Enum.sum()

    unique_declared_slots =
      raw_declared_occurrences - subset_declared_occurrences

    concrete_definitions = length(canonical_candidates)

    missing_id_slots =
      max(unique_declared_slots - concrete_definitions, 0)

    %{
      external_sets: external_sets,
      candidates: canonical_candidates,
      raw_declared_occurrences: raw_declared_occurrences,
      subset_declared_occurrences: subset_declared_occurrences,
      proven_duplicate_occurrences: subset_declared_occurrences,
      unique_declared_slots: unique_declared_slots,
      concrete_definitions: concrete_definitions,
      missing_id_slots: missing_id_slots,
      validation_errors: []
    }
  end

  # ---------------------------------------------------------------------------
  # External set normalization
  # ---------------------------------------------------------------------------

  defp normalize_external_sets(external_sets) when is_map(external_sets) do
    external_sets
    |> Enum.map(fn {set_id, set} ->
      normalize_external_set(to_string(set_id), set || %{})
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp normalize_external_set(set_id, set) do
    declared_count =
      integer_value(
        Map.get(set, "total_workflow_count") ||
          Map.get(set, "workflow_count") ||
          0
      )

    %{
      id: set_id,
      runtime: Map.get(set, "runtime"),
      relationship: Map.get(set, "relationship"),
      declared_count: declared_count,
      included_in_parent_total:
        truthy?(Map.get(set, "included_in_shadowmaker_tasks_total")),
      workflow_ids: normalize_workflow_ids(Map.get(set, "workflow_ids")),
      risk_groups: normalize_risk_groups(Map.get(set, "risk_groups")),
      raw: set
    }
  end

  defp normalize_workflow_ids(nil), do: []

  defp normalize_workflow_ids("not_yet_imported"), do: []

  defp normalize_workflow_ids(ids) when is_list(ids) do
    ids
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_workflow_ids(_), do: []

  defp normalize_risk_groups(nil), do: %{}

  defp normalize_risk_groups(groups) when is_map(groups) do
    groups
  end

  defp normalize_risk_groups(_), do: %{}

  # ---------------------------------------------------------------------------
  # Concrete candidate extraction
  # ---------------------------------------------------------------------------

  defp extract_concrete_candidates(set) do
    from_risk_groups =
      set.risk_groups
      |> Enum.flat_map(fn {risk_level, group} ->
        extract_risk_group_candidates(set, to_string(risk_level), group || %{})
      end)

    from_workflow_ids =
      Enum.map(set.workflow_ids, fn workflow_id ->
        candidate(
          set,
          workflow_id,
          infer_default_risk(set),
          infer_default_approval(set),
          nil,
          "workflow_ids"
        )
      end)

    (from_risk_groups ++ from_workflow_ids)
    |> dedupe_same_source_native_id()
  end

  defp extract_risk_group_candidates(set, risk_level, group) do
    workflows =
      group
      |> Map.get("workflows", [])
      |> List.wrap()
      |> Enum.map(&to_string/1)

    approval_required = truthy?(Map.get(group, "approval_required"))
    capability = Map.get(group, "capability")

    Enum.map(workflows, fn workflow_id ->
      candidate(
        set,
        workflow_id,
        risk_level,
        approval_required,
        capability,
        "risk_groups"
      )
    end)
  end

  defp candidate(
         set,
         workflow_id,
         risk_level,
         approval_required,
         capability,
         evidence_source
       ) do
    %{
      "source_set" => set.id,
      "source_native_id" => workflow_id,
      "relationship" => set.relationship,
      "included_in_parent_total" => set.included_in_parent_total,
      "runtime" => set.runtime,
      "risk_level" => normalize_risk(risk_level),
      "approval_required" => approval_required == true,
      "capability" => capability,
      "evidence_source" => evidence_source,
      "lifecycle_state" => "DISCOVERED",
      "executable" => false
    }
  end

  # ---------------------------------------------------------------------------
  # Candidate dedupe
  # ---------------------------------------------------------------------------

  defp dedupe_same_source_native_id(candidates) do
    candidates
    |> Enum.group_by(fn wf ->
      {wf["source_set"], wf["source_native_id"]}
    end)
    |> Enum.map(fn {_identity, occurrences} ->
      merge_same_identity!(occurrences)
    end)
    |> Enum.sort_by(&candidate_sort_key/1)
  end

  defp merge_same_identity!([candidate]), do: candidate

  defp merge_same_identity!(candidates) do
    fingerprints =
      candidates
      |> Enum.map(fn wf ->
        {
          wf["risk_level"],
          wf["approval_required"],
          wf["capability"],
          wf["runtime"]
        }
      end)
      |> Enum.uniq()

    if length(fingerprints) > 1 do
      first = hd(candidates)

      raise """
      conflicting duplicate source-native identity:
      source=#{first["source_set"]}
      id=#{first["source_native_id"]}
      fingerprints=#{inspect(fingerprints)}
      """
    end

    candidates
    |> Enum.sort_by(& &1["evidence_source"])
    |> hd()
  end

  # ---------------------------------------------------------------------------
  # Canonical IDs
  # ---------------------------------------------------------------------------

  defp assign_canonical_ids(candidates) do
    # External definitions are source-qualified so that the same native ID
    # from different proven sources remains distinct.
    Enum.map(candidates, fn wf ->
      source_slug = slugify(wf["source_set"])
      native_slug = slugify(wf["source_native_id"])

      canonical_id =
        @canonical_prefix <> source_slug <> "-" <> native_slug

      Map.put(wf, "canonical_id", canonical_id)
    end)
  end

  defp slugify(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace("_", "-")
    |> String.replace(~r/[^a-z0-9-]+/u, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  defp validate_report(report) do
    errors =
      []
      |> validate_arithmetic(report)
      |> validate_canonical_collisions(report)
      |> validate_candidates(report)
      |> Enum.uniq()
      |> Enum.sort()

    %{report | validation_errors: errors}
  end

  defp validate_arithmetic(errors, report) do
    expected =
      report.raw_declared_occurrences -
        report.subset_declared_occurrences

    errors =
      if expected == report.unique_declared_slots do
        errors
      else
        [
          "ARITHMETIC_INVARIANT_FAILED: expected=#{expected} actual=#{report.unique_declared_slots}"
          | errors
        ]
      end

    if report.concrete_definitions <= report.unique_declared_slots do
      errors
    else
      [
        "CONCRETE_DEFINITIONS_EXCEED_DECLARED_SLOTS: concrete=#{report.concrete_definitions} slots=#{report.unique_declared_slots}"
        | errors
      ]
    end
  end

  defp validate_canonical_collisions(errors, report) do
    collisions =
      report.candidates
      |> Enum.map(& &1["canonical_id"])
      |> Enum.frequencies()
      |> Enum.filter(fn {_id, count} -> count > 1 end)

    if collisions == [] do
      errors
    else
      ["CANONICAL_ID_COLLISION: #{inspect(collisions)}" | errors]
    end
  end

  defp validate_candidates(errors, report) do
    Enum.reduce(report.candidates, errors, fn wf, acc ->
      acc
      |> validate_candidate_id(wf)
      |> validate_candidate_risk(wf)
      |> validate_candidate_runtime(wf)
      |> validate_candidate_capability(wf)
      |> validate_candidate_approval(wf)
    end)
  end

  defp validate_candidate_id(errors, wf) do
    if blank?(wf["source_native_id"]) or blank?(wf["canonical_id"]) do
      ["MISSING_ID: #{inspect(wf)}" | errors]
    else
      errors
    end
  end

  defp validate_candidate_risk(errors, wf) do
    if wf["risk_level"] in ["L0", "L1", "L2", "L3"] do
      errors
    else
      [
        "UNKNOWN_RISK: #{wf["canonical_id"]}:#{inspect(wf["risk_level"])}"
        | errors
      ]
    end
  end

  defp validate_candidate_runtime(errors, wf) do
    if blank?(wf["runtime"]) do
      ["UNKNOWN_RUNTIME: #{wf["canonical_id"]}" | errors]
    else
      errors
    end
  end

  defp validate_candidate_capability(errors, wf) do
    if blank?(wf["capability"]) do
      ["MISSING_CAPABILITY: #{wf["canonical_id"]}" | errors]
    else
      errors
    end
  end

  defp validate_candidate_approval(errors, wf) do
    requires_approval = wf["risk_level"] in ["L2", "L3"]

    cond do
      requires_approval and wf["approval_required"] != true ->
        ["UNAPPROVED_L2_L3: #{wf["canonical_id"]}" | errors]

      true ->
        errors
    end
  end

  # ---------------------------------------------------------------------------
  # Reporting
  # ---------------------------------------------------------------------------

  defp print_report(report) do
    unknown_risk =
      Enum.count(report.candidates, fn wf ->
        wf["risk_level"] not in ["L0", "L1", "L2", "L3"]
      end)

    missing_capability =
      Enum.count(report.candidates, fn wf ->
        blank?(wf["capability"])
      end)

    unknown_runtime =
      Enum.count(report.candidates, fn wf ->
        blank?(wf["runtime"])
      end)

    canonical_collisions =
      report.candidates
      |> Enum.map(& &1["canonical_id"])
      |> Enum.frequencies()
      |> Enum.filter(fn {_id, count} -> count > 1 end)

    not_imported_sets =
      report.external_sets
      |> Enum.filter(fn set ->
        set.declared_count > 0 and
          set.workflow_ids == [] and
          map_size(set.risk_groups) == 0
      end)

    IO.puts("=== SET INVENTORY ===")

    Enum.each(report.external_sets, fn set ->
      concrete =
        Enum.count(report.candidates, fn wf ->
          wf["source_set"] == set.id
        end)

      IO.puts(
        [
          "SET=",
          set.id,
          " DECLARED=",
          Integer.to_string(set.declared_count),
          " CONCRETE=",
          Integer.to_string(concrete),
          " SUBSET=",
          boolean_text(set.included_in_parent_total),
          " RELATIONSHIP=",
          to_string(set.relationship || "UNKNOWN"),
          " RUNTIME=",
          to_string(set.runtime || "UNKNOWN")
        ]
        |> IO.iodata_to_binary()
      )
    end)

    IO.puts("")
    IO.puts("=== CONCRETE DEFINITIONS ===")

    Enum.each(report.candidates, fn wf ->
      IO.puts(
        "#{wf["canonical_id"]}" <>
          " | source=#{wf["source_set"]}" <>
          " | native=#{wf["source_native_id"]}" <>
          " | risk=#{wf["risk_level"]}" <>
          " | approval=#{wf["approval_required"]}" <>
          " | capability=#{wf["capability"] || "UNKNOWN"}" <>
          " | runtime=#{wf["runtime"] || "UNKNOWN"}"
      )
    end)

    IO.puts("")
    IO.puts("=== DRY-RUN REPORT ===")
    IO.puts("RAW_DECLARED_OCCURRENCES=#{report.raw_declared_occurrences}")
    IO.puts("SUBSET_OCCURRENCES=#{report.subset_declared_occurrences}")
    IO.puts("PROVEN_DUPLICATE_OCCURRENCES=#{report.proven_duplicate_occurrences}")
    IO.puts("UNIQUE_DECLARED_SLOTS=#{report.unique_declared_slots}")
    IO.puts("CONCRETE_DEFINITIONS=#{report.concrete_definitions}")
    IO.puts("NOT_IMPORTED_ID_SLOTS=#{report.missing_id_slots}")
    IO.puts("NOT_IMPORTED_SETS=#{length(not_imported_sets)}")
    IO.puts("DEDUPED_UNIQUE_CONCRETE=#{report.concrete_definitions}")
    IO.puts("UNKNOWN_RISK=#{unknown_risk}")
    IO.puts("MISSING_CAPABILITY=#{missing_capability}")
    IO.puts("UNKNOWN_RUNTIME=#{unknown_runtime}")
    IO.puts("CANONICAL_COLLISIONS=#{canonical_collisions}")
    IO.puts("VALIDATION_ERRORS=#{length(report.validation_errors)}")
    IO.puts("REGISTRY_MUTATION=NO")
    IO.puts("RUNTIME_EXECUTION=NO")
    IO.puts("4013_MUTATION=NO")
    IO.puts("4014_MUTATION=NO")
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp infer_default_risk(_set), do: "UNKNOWN"

  defp infer_default_approval(set) do
    set.raw
    |> Map.get("approval_required", false)
    |> truthy?()
  end

  defp normalize_risk(value) when value in ["L0", "L1", "L2", "L3"],
    do: value

  defp normalize_risk(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_risk()

  defp normalize_risk(_),
    do: "UNKNOWN"

  defp candidate_sort_key(wf) do
    {
      wf["source_set"],
      wf["source_native_id"],
      wf["risk_level"]
    }
  end

  defp integer_value(value) when is_integer(value), do: value

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> 0
    end
  end

  defp integer_value(_), do: 0

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("TRUE"), do: true
  defp truthy?(1), do: true
  defp truthy?(_), do: false

  defp blank?(nil), do: true
  defp blank?(""), do: true

  defp blank?(value) when is_binary(value),
    do: String.trim(value) == ""

  defp blank?(_),
    do: false

  defp boolean_text(true), do: "true"
  defp boolean_text(false), do: "false"
end

ImportExternalWorkflows.main(System.argv())
ELIXIR