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
    root = Path.expand(home || System.user_home!())

    case latest_report(root) do
      nil -> not_configured()
      report -> load_report(root, report)
    end
  end

  defp load_report(root, report) do
    entrypoints = Path.join(report, "entrypoints.tsv")

    case File.read(entrypoints) do
      {:ok, body} ->
        {records, rejected} = parse_records(body, root)

        %{
          status: if(records == [], do: "NOT_CONFIGURED", else: "DISCOVERED"),
          source_type: "LOCAL_WORKFLOW_CORRELATION",
          synthetic: false,
          real_data: records != [],
          reachable: records != [],
          executable: false,
          integration_mode: "REFERENCE_ONLY",
          report_ref: Path.relative_to(report, root),
          counts: %{
            registered: length(records),
            rejected: rejected,
            max_records: @max_records
          },
          records: records
        }

      {:error, _} ->
        not_configured()
    end
  end

  defp parse_records(body, root) do
    body
    |> String.split("\n", trim: true)
    |> Enum.drop(1)
    |> Enum.reduce({[], 0}, fn line, {records, rejected} ->
      case parse_line(line, root) do
        {:ok, record} when length(records) < @max_records -> {[record | records], rejected}
        {:ok, _record} -> {records, rejected + 1}
        :reject -> {records, rejected + 1}
      end
    end)
    |> then(fn {records, rejected} ->
      {records |> Enum.reverse() |> Enum.sort_by(& &1.id), rejected}
    end)
  end

  defp parse_line(line, root) do
    case String.split(line, "\t") do
      [source, type, path] -> build_record(source, type, path, root)
      _ -> :reject
    end
  end

  defp build_record(source, type, path, root) do
    expanded = Path.expand(path)

    with true <- MapSet.member?(@allowed_sources, source),
         true <- MapSet.member?(@allowed_types, type),
         true <- inside_root?(expanded, root),
         true <- regular_file?(expanded),
         relative <- Path.relative_to(expanded, root),
         false <- excluded_path?(relative) do
      {:ok,
       %{
         id: stable_id(source, relative),
         name: friendly_name(Path.basename(relative)),
         source: source,
         kind: type,
         domain: infer_domain(relative),
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
         source_ref: relative
       }}
    else
      _ -> :reject
    end
  end

  defp latest_report(root) do
    reports_root = Path.join(root, "reports/shadowops")

    case File.ls(reports_root) do
      {:ok, names} ->
        names
        |> Enum.filter(fn name ->
          String.starts_with?(name, "workflow_correlation_") and
            File.regular?(Path.join([reports_root, name, "entrypoints.tsv"]))
        end)
        |> Enum.map(&Path.join(reports_root, &1))
        |> Enum.max_by(&report_mtime/1, fn -> nil end)

      {:error, _reason} ->
        nil
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

  defp not_configured do
    %{
      status: "NOT_CONFIGURED",
      source_type: "LOCAL_WORKFLOW_CORRELATION",
      synthetic: false,
      real_data: false,
      reachable: false,
      executable: false,
      integration_mode: "REFERENCE_ONLY",
      report_ref: nil,
      counts: %{registered: 0, rejected: 0, max_records: @max_records},
      records: []
    }
  end
end
