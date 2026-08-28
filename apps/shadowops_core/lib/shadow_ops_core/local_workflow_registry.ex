defmodule ShadowOpsCore.LocalWorkflowRegistry do
  @moduledoc """
  Read-only registry projection for locally discovered workflow entrypoints.

  The registry consumes the latest workflow correlation evidence under the configured
  home directory. Every accepted entry receives a deterministic ID derived from its
  source and relative path. Registration is evidence-only: records remain DISCOVERED,
  REFERENCE_ONLY and non-executable until a concrete runtime adapter and governance
  mapping are proven elsewhere.
  """

  @max_records 500
  @allowed_sources MapSet.new([
                     "Projects",
                     "DokumentenSystem",
                     "ProofFlow-Obsidian-Vault",
                     "actions-runner-host",
                     "auto_bewerbungen",
                     "whatsapp-agent",
                     "matrix_shadowops",
                     "shadowops-local-hold",
                     "openclaw-workspace"
                   ])
  @allowed_types MapSet.new([
                   "SYSTEMD_SERVICE",
                   "SYSTEMD_TIMER",
                   "SHELL_WORKFLOW",
                   "PYTHON_WORKFLOW",
                   "ELIXIR_WORKFLOW",
                   "GITHUB_ACTION"
                 ])

  @spec snapshot(String.t() | nil) :: map()
  def snapshot(home \\ nil) do
    inventory = inventory(home)

    records =
      inventory.records
      |> Enum.filter(&(&1.registration_state == "LOCALWF_REGISTERED"))
      |> Enum.map(& &1.registry_record)
      |> Enum.sort_by(& &1.id)

    %{
      status: if(records == [], do: "NOT_CONFIGURED", else: "DISCOVERED"),
      source_type: "LOCAL_WORKFLOW_CORRELATION",
      synthetic: false,
      real_data: records != [],
      reachable: records != [],
      executable: false,
      integration_mode: "REFERENCE_ONLY",
      report_ref: inventory.report_ref,
      counts: %{
        registered: length(records),
        rejected:
          inventory.counts.raw_rejected_policy + inventory.counts.raw_duplicates +
            inventory.counts.raw_unknown + inventory.counts.raw_eligible_unregistered,
        max_records: @max_records,
        raw_discovered_total: inventory.counts.raw_discovered_total,
        raw_eligible_registered: inventory.counts.raw_eligible_registered,
        raw_eligible_unregistered: inventory.counts.raw_eligible_unregistered,
        raw_rejected_policy: inventory.counts.raw_rejected_policy,
        raw_duplicates: inventory.counts.raw_duplicates,
        raw_unknown: inventory.counts.raw_unknown
      },
      records: records
    }
  end

  @doc "Returns metadata-only accounting for every row in the latest correlation report."
  @spec inventory(String.t() | nil) :: map()
  def inventory(home \\ nil) do
    root = Path.expand(home || System.user_home!())

    case latest_report(root) do
      nil -> empty_inventory()
      report -> load_inventory(root, report)
    end
  end

  @doc "Returns the repository's deterministic evidence identity for a source reference."
  def expected_id(source, source_ref)
      when is_binary(source) and source != "" and is_binary(source_ref) and source_ref != "" do
    stable_id(source, source_ref)
  end

  def expected_id(_, _), do: nil

  defp load_inventory(root, report) do
    entrypoints = Path.join(report, "entrypoints.tsv")

    case File.read(entrypoints) do
      {:ok, body} ->
        records = parse_inventory(body, root)
        frequencies = Enum.frequencies_by(records, & &1.accounting_state)

        %{
          report_ref: Path.relative_to(report, root),
          counts: %{
            raw_discovered_total: length(records),
            raw_eligible_registered: Map.get(frequencies, :eligible_registered, 0),
            raw_eligible_unregistered: Map.get(frequencies, :eligible_unregistered, 0),
            raw_rejected_policy: Map.get(frequencies, :rejected_policy, 0),
            raw_duplicates: Map.get(frequencies, :duplicate, 0),
            raw_unknown: Map.get(frequencies, :unknown, 0)
          },
          records: records
        }

      {:error, _} ->
        empty_inventory()
    end
  end

  defp parse_inventory(body, root) do
    body
    |> String.split("\n", trim: true)
    |> Enum.drop(1)
    |> Enum.reduce({[], MapSet.new(), 0}, fn line, {records, seen, registered} ->
      candidate = parse_line(line, root)

      cond do
        candidate.accounting_state != :eligible ->
          {[candidate | records], seen, registered}

        MapSet.member?(seen, candidate.expected_local_id) ->
          duplicate =
            candidate
            |> Map.put(:accounting_state, :duplicate)
            |> Map.put(:registration_state, "DUPLICATE")
            |> Map.put(:rejection_reason, "DUPLICATE_IDENTITY")

          {[duplicate | records], seen, registered}

        registered < @max_records ->
          accepted =
            candidate
            |> Map.put(:accounting_state, :eligible_registered)
            |> Map.put(:registration_state, "LOCALWF_REGISTERED")

          {[accepted | records], MapSet.put(seen, candidate.expected_local_id), registered + 1}

        true ->
          rejected =
            candidate
            |> Map.put(:accounting_state, :rejected_policy)
            |> Map.put(:registration_state, "REJECTED_POLICY")
            |> Map.put(:rejection_reason, "RECORD_LIMIT")

          {[rejected | records], MapSet.put(seen, candidate.expected_local_id), registered}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp parse_line(line, root) do
    case String.split(line, "\t") do
      [source, type, path] -> build_candidate(source, type, path, root)
      _ -> unknown_candidate()
    end
  end

  defp build_candidate(source, type, path, root) do
    expanded =
      if(Path.type(path) == :absolute, do: Path.expand(path), else: Path.expand(path, root))

    inside_allowed_root = inside_root?(expanded, root)

    source_ref =
      if(inside_allowed_root, do: Path.relative_to(expanded, root), else: Path.basename(path))

    file_exists = File.exists?(expanded)
    regular_file = regular_file?(expanded)
    excluded_path = inside_allowed_root and excluded_path?(source_ref)

    rejection_reason =
      cond do
        not MapSet.member?(@allowed_sources, source) -> "SOURCE_NOT_ALLOWED"
        not MapSet.member?(@allowed_types, type) -> "TYPE_NOT_ALLOWED"
        not inside_allowed_root -> "OUTSIDE_ALLOWED_ROOT"
        not file_exists -> "FILE_MISSING"
        not regular_file -> "NOT_REGULAR_FILE"
        excluded_path -> "EXCLUDED_PATH"
        true -> nil
      end

    id = expected_id(source, source_ref)

    %{
      workflow_identity: id,
      source: source,
      source_ref: source_ref,
      type: type,
      file_exists: file_exists,
      regular_file: regular_file,
      inside_allowed_root: inside_allowed_root,
      excluded_path: excluded_path,
      expected_local_id: id,
      registration_state: if(rejection_reason, do: "REJECTED_POLICY", else: "RAW_DISCOVERED"),
      rejection_reason: rejection_reason,
      accounting_state: if(rejection_reason, do: :rejected_policy, else: :eligible),
      registry_record:
        if(rejection_reason, do: nil, else: registry_record(id, source, type, source_ref))
    }
  end

  defp registry_record(id, source, type, source_ref) do
    %{
      id: id,
      name: friendly_name(Path.basename(source_ref)),
      source: source,
      kind: type,
      domain: infer_domain(source_ref),
      status: "DISCOVERED",
      execution_status: "DISCOVERED",
      real_data: true,
      synthetic: false,
      reachable: true,
      executable: false,
      integration_mode: "REFERENCE_ONLY",
      runtime_verified: false,
      governance_mapped: false,
      risk_level: "UNKNOWN",
      source_kind: "local_workflow_evidence",
      source_ref: source_ref
    }
  end

  defp unknown_candidate do
    %{
      workflow_identity: nil,
      source: "UNKNOWN",
      source_ref: "UNKNOWN",
      type: "UNKNOWN",
      file_exists: false,
      regular_file: false,
      inside_allowed_root: false,
      excluded_path: false,
      expected_local_id: nil,
      registration_state: "BLOCKED_UNKNOWN",
      rejection_reason: "MALFORMED_ROW",
      accounting_state: :unknown,
      registry_record: nil
    }
  end

  defp latest_report(root) do
    reports_root = Path.join(root, "reports/shadowops")

    with {:ok, names} <- File.ls(reports_root) do
      names
      |> Enum.filter(&String.starts_with?(&1, "workflow_correlation_"))
      |> Enum.map(&Path.join(reports_root, &1))
      |> Enum.filter(&File.dir?/1)
      |> Enum.filter(&File.regular?(Path.join(&1, "entrypoints.tsv")))
      |> Enum.max_by(&report_mtime/1, fn -> nil end)
    else
      _ -> nil
    end
  end

  defp report_mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, stat} -> stat.mtime
      _ -> 0
    end
  end

  defp excluded_path?(relative) do
    lower = String.downcase(relative)
    basename = Path.basename(lower)
    segments = Path.split(lower)

    ignored_segments = [
      "test",
      "tests",
      "fixtures",
      "deps",
      "_build",
      "node_modules",
      "vendor",
      "config",
      ".venv",
      "venv",
      "site-packages",
      "__pycache__",
      ".pytest_cache",
      ".mypy_cache",
      ".ruff_cache",
      ".tox",
      "dist",
      "build"
    ]

    Enum.any?(segments, &(&1 in ignored_segments)) or
      basename in [
        "mix.exs",
        ".formatter.exs",
        "test_helper.exs",
        "__init__.py"
      ] or
      String.ends_with?(basename, "_test.exs") or
      String.ends_with?(basename, "_test.py") or
      String.starts_with?(basename, "test_")
  end

  defp infer_domain(relative) do
    lower = String.downcase(relative)

    cond do
      contains_any?(lower, ["whatsapp", "telegram", "facebook", "social"]) ->
        "social"

      contains_any?(lower, ["career", "bewerb", "income"]) ->
        "career"

      contains_any?(lower, ["security", "audit", "governance", "zero-trust", "zero_trust"]) ->
        "security"

      contains_any?(lower, ["knowledge", "obsidian", "rag", "research", "document", "dokument"]) ->
        "knowledge"

      contains_any?(lower, ["backup", "archive", "timeshift"]) ->
        "backups"

      contains_any?(lower, ["agent", "ai", "openclaw"]) ->
        "agents"

      contains_any?(lower, ["github", ".github/workflows"]) ->
        "ci"

      true ->
        "system"
    end
  end

  defp stable_id(source, relative) do
    digest =
      :crypto.hash(:sha256, source <> "\0" <> relative)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)

    "localwf_#{slug(source)}_#{digest}"
  end

  defp friendly_name(basename) do
    basename
    |> Path.rootname()
    |> String.replace(~r/[-_]+/, " ")
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp contains_any?(value, needles), do: Enum.any?(needles, &String.contains?(value, &1))

  defp inside_root?(path, root), do: path == root or String.starts_with?(path, root <> "/")

  defp regular_file?(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular}} -> true
      _ -> false
    end
  end

  defp empty_inventory do
    %{
      report_ref: nil,
      counts: %{
        raw_discovered_total: 0,
        raw_eligible_registered: 0,
        raw_eligible_unregistered: 0,
        raw_rejected_policy: 0,
        raw_duplicates: 0,
        raw_unknown: 0
      },
      records: []
    }
  end
end
