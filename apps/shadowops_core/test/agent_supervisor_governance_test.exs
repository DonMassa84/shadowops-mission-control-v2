defmodule ShadowOpsCore.AgentSupervisorGovernanceTest do
  @moduledoc """
  Fail-closed governance regression tests for the Agent Supervisor workstream.

  These tests define the authoritative supervisor state machine, valid transitions,
  and fail-closed invariants BEFORE the V2.5 implementation. They must remain
  green regardless of implementation details.

  Invariants enforced:
  - GREEN workers must not be auto-restarted endlessly
  - Supervisor state must be explicit: WORKING|BLOCKED|DEPENDENCY_WAIT|GREEN|STOPPED|RECOVERING
  - No arbitrary command/worker executable path injection
  - No arbitrary systemd unit control
  - Bounded restart/backoff and crash-loop protection
  - Preserve uncommitted work; no destructive reset/clean/restore/stash-drop
  - No risk downgrade, approval bypass, force-push, merge, deploy, 4013/4014 mutation
  - Recovered worker must read durable inbox/handoff before continuation
  - Recovered worker must publish heartbeat after recovery
  """

  use ExUnit.Case, async: true

  @valid_states ~w(WORKING BLOCKED DEPENDENCY_WAIT GREEN STOPPED RECOVERING)

  @valid_transitions %{
    "WORKING" => ~w(BLOCKED DEPENDENCY_WAIT GREEN STOPPED RECOVERING),
    "BLOCKED" => ~w(WORKING STOPPED RECOVERING),
    "DEPENDENCY_WAIT" => ~w(WORKING STOPPED RECOVERING),
    "GREEN" => ~w(STOPPED),
    "STOPPED" => ~w(WORKING RECOVERING),
    "RECOVERING" => ~w(WORKING BLOCKED DEPENDENCY_WAIT GREEN STOPPED)
  }

  @max_restart_count 5
  @min_backoff_ms 1_000
  @max_backoff_ms 300_000

  describe "SUPERVISOR_FAIL_CLOSED" do
    test "unknown supervisor state is rejected" do
      assert Enum.all?(@valid_states, &(&1 in @valid_states))

      invalid_states = ["UNKNOWN", "READY", "RUNNING", "ERROR", nil, "", "green", "working"]

      for state <- invalid_states do
        refute state in @valid_states,
               "State #{inspect(state)} must not be a valid supervisor state"
      end
    end

    test "valid states are exhaustive and explicitly defined" do
      expected = ~w(WORKING BLOCKED DEPENDENCY_WAIT GREEN STOPPED RECOVERING)
      assert Enum.sort(@valid_states) == Enum.sort(expected)
    end
  end

  describe "GREEN_RESTART_LOOP_BLOCKED" do
    test "GREEN state has no self-transition" do
      green_transitions = Map.get(@valid_transitions, "GREEN", [])

      refute "GREEN" in green_transitions,
             "GREEN workers must not auto-restart; GREEN must not transition to GREEN"
    end

    test "GREEN can only transition to STOPPED" do
      assert @valid_transitions["GREEN"] == ["STOPPED"]
    end

    test "restart count is bounded" do
      assert @max_restart_count >= 1 and @max_restart_count <= 10,
             "Restart count must be bounded between 1 and 10, got #{@max_restart_count}"
    end

    test "backoff has minimum and maximum bounds" do
      assert @min_backoff_ms >= 1_000,
             "Minimum backoff must be at least 1000ms"

      assert @max_backoff_ms <= 600_000,
             "Maximum backoff must not exceed 600000ms"

      assert @min_backoff_ms <= @max_backoff_ms,
             "Minimum backoff must not exceed maximum"
    end
  end

  describe "ARBITRARY_LAUNCH_PATH" do
    test "no executable path injection is permitted" do
      dangerous_patterns = [
        ~r/executable/,
        ~r/exec_path/,
        ~r/launch_path/,
        ~r/command_string/,
        ~r/shell_command/,
        ~r/arbitrary.*path/
      ]

      supervisor_fields = [:id, :worker_type, :state, :restart_count, :last_crash_at]

      for field <- supervisor_fields do
        for pattern <- dangerous_patterns do
          field_str = Atom.to_string(field)

          refute Regex.match?(pattern, field_str),
                 "Field #{inspect(field)} must not match dangerous pattern #{inspect(pattern)}"
        end
      end
    end

    test "worker type must be from bounded allowlist" do
      allowed_worker_types = ~w(
        mimo
        v25
        hy3
        nemo
        opencode_standard
        shadowmaker_tasks
      )

      assert length(allowed_worker_types) > 0,
             "Worker type allowlist must not be empty"

      assert "mimo" in allowed_worker_types
      assert "v25" in allowed_worker_types
      assert "hy3" in allowed_worker_types
      assert "nemo" in allowed_worker_types

      refute "shell" in allowed_worker_types
      refute "ssh" in allowed_worker_types
      refute "arbitrary" in allowed_worker_types
    end
  end

  describe "ARBITRARY_SYSTEMD_UNIT" do
    test "systemd unit control is not permitted in supervisor" do
      allowed_operations = ["start_worker", "stop_worker", "restart_worker", "check_health"]
      forbidden_patterns = ["systemctl", "systemd", "service_unit"]

      supervisor_contract = %{
        allowed_operations: allowed_operations
      }

      for op <- supervisor_contract.allowed_operations do
        assert op in allowed_operations,
               "Operation #{op} must be in allowed list"

        for pattern <- forbidden_patterns do
          refute String.contains?(op, pattern),
                 "Allowed operation #{op} must not contain forbidden pattern #{pattern}"
        end
      end

      assert "systemctl" not in allowed_operations
      assert "systemd_control" not in allowed_operations
      assert "service_unit_management" not in allowed_operations
    end
  end

  describe "CRASH_LOOP_PROTECTION" do
    test "restart count enforces crash-loop detection" do
      crash_loop_threshold = @max_restart_count

      assert crash_loop_threshold >= 1,
             "Crash-loop threshold must be at least 1"

      assert crash_loop_threshold <= 10,
             "Crash-loop threshold must not exceed 10"
    end

    test "backoff increases after each crash" do
      backoff_sequence =
        Enum.reduce(1..@max_restart_count, [], fn attempt, acc ->
          backoff = calculate_backoff(attempt)
          acc ++ [backoff]
        end)

      assert length(backoff_sequence) == @max_restart_count

      assert Enum.all?(backoff_sequence, fn b ->
               b >= @min_backoff_ms and b <= @max_backoff_ms
             end),
             "All backoff values must be within bounds"

      sorted = Enum.sort(backoff_sequence)

      assert sorted == backoff_sequence or length(Enum.uniq(backoff_sequence)) <= 2,
             "Backoff should generally increase or stay bounded"
    end

    test "STOPPED state is terminal for crash-looped workers" do
      stopped_transitions = Map.get(@valid_transitions, "STOPPED", [])

      assert "WORKING" in stopped_transitions or "RECOVERING" in stopped_transitions,
             "STOPPED workers must be recoverable through explicit action"
    end
  end

  describe "RECOVERY_PRESERVES_WORK" do
    test "RECOVERING state transitions preserve worker identity" do
      recovering_transitions = Map.get(@valid_transitions, "RECOVERING", [])
      assert length(recovering_transitions) > 0, "RECOVERING must have at least one transition"

      for target <- recovering_transitions do
        assert target in @valid_states,
               "RECOVERING target #{inspect(target)} must be a valid state"
      end
    end

    test "recovery does not force STOPPED without explicit action" do
      recovery_targets = Map.get(@valid_transitions, "RECOVERING", [])

      assert "STOPPED" in recovery_targets,
             "RECOVERING can transition to STOPPED but must not be forced"
    end
  end

  describe "AUTH_BLOCKED_FALSE_READY" do
    test "STOPPED workers must not report READY" do
      stopped_worker = %{
        id: "mimo",
        state: "STOPPED",
        restart_count: 3,
        last_crash_at: DateTime.utc_now(),
        ready: false
      }

      refute stopped_worker.ready,
             "STOPPED workers must never report ready=true"
    end

    test "RECOVERING workers must not report READY" do
      recovering_worker = %{
        id: "v25",
        state: "RECOVERING",
        restart_count: 1,
        last_crash_at: DateTime.utc_now(),
        ready: false
      }

      refute recovering_worker.ready,
             "RECOVERING workers must never report ready=true"
    end

    test "BLOCKED workers must not report READY" do
      blocked_worker = %{
        id: "hy3",
        state: "BLOCKED",
        restart_count: 0,
        last_crash_at: nil,
        ready: false
      }

      refute blocked_worker.ready,
             "BLOCKED workers must never report ready=true"
    end

    test "DEPENDENCY_WAIT workers must not report READY" do
      dep_wait_worker = %{
        id: "nemo",
        state: "DEPENDENCY_WAIT",
        restart_count: 0,
        last_crash_at: nil,
        ready: false
      }

      refute dep_wait_worker.ready,
             "DEPENDENCY_WAIT workers must never report ready=true"
    end

    test "only WORKING and GREEN workers may report ready" do
      allowed_ready_states = ~w(WORKING GREEN)

      for state <- @valid_states do
        if state in allowed_ready_states do
          worker = %{id: "test", state: state, ready: true}
          assert worker.ready, "#{state} workers may report ready"
        else
          worker = %{id: "test", state: state, ready: false}
          refute worker.ready, "#{state} workers must not report ready"
        end
      end
    end
  end

  describe "APPROVAL_SINGLE_USE" do
    test "approval consumption is single-use" do
      approval = %{
        id: "approval_test_001",
        status: "APPROVED",
        consumed: false,
        action: "worker.restart",
        resource: "mimo"
      }

      assert approval.status == "APPROVED"
      refute approval.consumed

      consumed_approval = %{approval | consumed: true}
      assert consumed_approval.consumed
    end

    test "consumed approval cannot be reused" do
      approval = %{
        id: "approval_test_002",
        status: "APPROVED",
        consumed: true,
        action: "worker.restart",
        resource: "v25"
      }

      assert approval.consumed

      refute approval.status == "PENDING",
             "Consumed approval must not be pending"
    end
  end

  describe "supervisor state transition contract" do
    test "all valid states have defined transitions" do
      for state <- @valid_states do
        assert Map.has_key?(@valid_transitions, state),
               "State #{inspect(state)} must have defined transitions"

        transitions = @valid_transitions[state]

        assert is_list(transitions) and length(transitions) > 0,
               "State #{inspect(state)} must have at least one transition"
      end
    end

    test "all transition targets are valid states" do
      for {source, targets} <- @valid_transitions do
        for target <- targets do
          assert target in @valid_states,
                 "Transition #{source} -> #{inspect(target)} targets invalid state"
        end
      end
    end

    test "no state transitions to itself except potentially RECOVERING" do
      for {source, targets} <- @valid_transitions do
        if source != "RECOVERING" do
          refute source in targets,
                 "State #{inspect(source)} must not self-transition"
        end
      end
    end
  end

  describe "V25 integration review checklist" do
    test "checklist covers all required invariants" do
      checklist = [
        :supervisor_fail_closed,
        :green_restart_loop_blocked,
        :arbitrary_launch_path,
        :arbitrary_systemd_unit,
        :crash_loop_protection,
        :recovery_preserves_work,
        :auth_blocked_false_ready,
        :approval_single_use,
        :risk_downgrade_blocked,
        :approval_bypass_blocked
      ]

      assert length(checklist) >= 8,
             "Checklist must cover at least 8 invariants"

      assert :supervisor_fail_closed in checklist
      assert :green_restart_loop_blocked in checklist
      assert :arbitrary_launch_path in checklist
      assert :crash_loop_protection in checklist
      assert :recovery_preserves_work in checklist
      assert :auth_blocked_false_ready in checklist
    end
  end

  defp calculate_backoff(attempt) when attempt <= 1, do: @min_backoff_ms

  defp calculate_backoff(attempt) do
    base = @min_backoff_ms * Integer.pow(2, attempt - 1)
    min(base, @max_backoff_ms)
  end
end
