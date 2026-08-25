defmodule ShadowOpsCore.ResultEvaluator do
  @moduledoc """
  Deterministic post-execution evaluation for ShadowOps runs.

  Technical truth is derived from exit codes and observed runtime state. AI summaries may be
  added later, but they never override these checks or promote failed evidence to PASS.
  """

  @type check :: %{id: String.t(), status: String.t(), detail: String.t()}

  def workflow(result, exit_code) do
    checks = [
      check("execution_exit_code", exit_code == 0, "exit_code=#{inspect(exit_code)}"),
      check(
        "result_present",
        present?(result),
        if(present?(result), do: "result captured", else: "result missing")
      )
    ]

    build("workflow", checks)
  end

  def service(action, before_state, after_state, execution_status \\ :ok)
      when action in ["start", "restart", "stop"] do
    after_active = value(after_state, :active_state)

    state_ok =
      case action do
        action when action in ["start", "restart"] -> after_active == "active"
        "stop" -> after_active == "inactive"
      end

    checks = [
      check(
        "execution_command",
        execution_status == :ok,
        "execution_status=#{execution_status}"
      ),
      check(
        "service_state",
        state_ok,
        "before=#{value(before_state, :active_state) || "unknown"}; after=#{after_active || "unknown"}; action=#{action}"
      )
    ]

    checks = maybe_restart_pid_check(checks, action, before_state, after_state)
    build("service", checks)
  end

  def blocked(kind, reason) do
    %{
      kind: kind,
      verdict: "BLOCKED",
      score: 0,
      checks: [check("governance", false, safe_text(reason))],
      summary: "Execution was blocked before a successful technical outcome could be verified."
    }
  end

  defp maybe_restart_pid_check(checks, "restart", before_state, after_state) do
    before_pid = value(before_state, :pid)
    after_pid = value(after_state, :pid)

    if measurable_pid?(before_pid) and measurable_pid?(after_pid) do
      checks ++
        [
          check(
            "process_replaced",
            before_pid != after_pid,
            "before_pid=#{before_pid}; after_pid=#{after_pid}"
          )
        ]
    else
      checks
    end
  end

  defp maybe_restart_pid_check(checks, _action, _before_state, _after_state), do: checks

  defp build(kind, checks) do
    total = length(checks)
    passed = Enum.count(checks, &(&1.status == "PASS"))
    score = if total == 0, do: 0, else: round(passed / total * 100)

    %{
      kind: kind,
      verdict: verdict(score),
      score: score,
      checks: checks,
      summary: "#{passed}/#{total} deterministic technical checks passed."
    }
  end

  defp verdict(100), do: "EXCELLENT"
  defp verdict(score) when score >= 80, do: "HEALTHY"
  defp verdict(score) when score >= 60, do: "REVIEW"
  defp verdict(_), do: "CRITICAL"

  defp check(id, true, detail), do: %{id: id, status: "PASS", detail: detail}
  defp check(id, false, detail), do: %{id: id, status: "FAIL", detail: detail}

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_map(value), do: map_size(value) > 0
  defp present?(value) when is_list(value), do: value != []
  defp present?(nil), do: false
  defp present?(_), do: true

  defp measurable_pid?(pid) when is_integer(pid), do: pid > 0
  defp measurable_pid?(pid) when is_binary(pid), do: pid not in ["", "0"]
  defp measurable_pid?(_), do: false

  defp value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp value(_, _), do: nil

  defp safe_text(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_text({tag, _}) when is_atom(tag), do: Atom.to_string(tag)
  defp safe_text(_), do: "execution_blocked"
end
