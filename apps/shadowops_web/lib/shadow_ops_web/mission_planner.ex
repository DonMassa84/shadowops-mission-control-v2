defmodule ShadowOpsWeb.MissionPlanner do
  @moduledoc """
  Deterministic, evidence-backed current mission and next-action projection.

  The planner does not generate tasks with AI. It only ranks actions that are directly derived
  from verified ShadowOps runtime state or the allowlisted LearningFocus configuration.
  """

  alias ShadowOpsCore.{JobQueue, LearningFocus}
  alias ShadowOpsWeb.{IntegrationCatalog, RuntimeOverview}

  @positive ~w(READY HEALTHY VALID AVAILABLE ONLINE CONNECTED PASS)

  def snapshot do
    overview = RuntimeOverview.snapshot()
    {:ok, focus} = LearningFocus.load()

    build(overview, focus, IntegrationCatalog.snapshot(), JobQueue.snapshot())
  rescue
    error ->
      %{
        status: "UNAVAILABLE",
        source: "mission planner",
        mission: unavailable_mission(Exception.message(error)),
        actions: []
      }
  end

  @doc false
  def build(overview, focus, integrations, jobs)
      when is_map(overview) and is_map(focus) and is_map(integrations) and is_map(jobs) do
    mission = mission_from_focus(focus)

    actions =
      operational_candidates(overview, integrations, jobs) ++ focus_candidates(focus)

    actions =
      actions
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(fn action -> {-action.priority, action.id} end)
      |> Enum.take(3)

    %{
      status: if(mission.status == "READY" or actions != [], do: "READY", else: "UNAVAILABLE"),
      source: "runtime overview + integration catalog + job queue + LearningFocus",
      mission: mission,
      actions: actions
    }
  end

  defp mission_from_focus(focus) do
    if normalized(value(focus, :availability)) == "AVAILABLE" do
      goal = value(focus, :goal, %{})
      current = value(focus, :current, %{})
      title = value(goal, :title) || value(current, :title)
      current_title = value(current, :title)

      if is_binary(title) and title != "" and is_binary(current_title) and current_title != "" do
        %{
          status: "READY",
          title: title,
          objective: value(goal, :smart),
          current: current_title,
          instruction: value(current, :instruction),
          done_when: value(current, :done_when),
          context: value(focus, :active_context, "general"),
          source: value(focus, :source, "LearningFocus")
        }
      else
        unavailable_mission("LearningFocus does not contain a valid current mission")
      end
    else
      unavailable_mission(value(focus, :detail, "LearningFocus is unavailable"))
    end
  end

  defp operational_candidates(overview, integrations, jobs) do
    approvals = nested(overview, [:approvals, :records], [])
    pending = Enum.count(approvals, &(normalized(value(&1, :status)) == "PENDING"))
    readiness = nested(overview, [:readiness, :state])
    security = nested(overview, [:security, :overall])
    audit = nested(overview, [:audit, :state])
    backups = nested(overview, [:backups, :status])
    integration_status = value(integrations, :status)
    jobs_status = value(jobs, :status)

    [
      if(pending > 0,
        do:
          action(
            "pending-approvals",
            100,
            "Review #{pending} pending approval#{if(pending == 1, do: "", else: "s")}",
            "Governed actions are waiting for an operator decision.",
            "/approvals",
            "approval store"
          )
      ),
      unhealthy_action(
        "runtime-readiness",
        95,
        readiness,
        "Restore runtime readiness",
        "A required runtime readiness gate is not positive.",
        "/infrastructure",
        "runtime readiness"
      ),
      unhealthy_action(
        "security-gate",
        90,
        security,
        "Review security gate",
        "The current security projection is not positive.",
        "/security",
        "security status"
      ),
      unhealthy_action(
        "audit-chain",
        88,
        audit,
        "Verify audit chain",
        "Audit-chain state is not positive.",
        "/audit",
        "audit verification"
      ),
      unhealthy_action(
        "required-integrations",
        85,
        integration_status,
        "Resolve required integration health",
        "One or more required core integrations are not ready.",
        "/integrations",
        "integration catalog"
      ),
      unhealthy_action(
        "backups",
        60,
        backups,
        "Review backup state",
        "Backup state is not positive.",
        "/backups",
        "backup projection"
      ),
      if(normalized(jobs_status) in ["FAIL", "DEGRADED", "UNAVAILABLE"],
        do:
          action(
            "job-queue",
            65,
            "Review job queue",
            "Persistent workload state needs attention.",
            "/jobs",
            "job queue"
          )
      )
    ]
  end

  defp focus_candidates(focus) do
    if normalized(value(focus, :availability)) == "AVAILABLE" do
      current = value(focus, :current, %{})
      current_title = value(current, :title)
      instruction = value(current, :instruction)

      current_action =
        if is_binary(current_title) and current_title != "" do
          action(
            "focus-current",
            80,
            current_title,
            instruction || "Continue the configured current focus.",
            "/focus",
            value(focus, :source, "LearningFocus")
          )
        end

      next_actions =
        focus
        |> value(:next, [])
        |> List.wrap()
        |> Enum.filter(&(is_binary(&1) and &1 != ""))
        |> Enum.take(3)
        |> Enum.with_index()
        |> Enum.map(fn {title, index} ->
          action(
            "focus-next-#{index + 1}",
            74 - index,
            title,
            "Configured next step from LearningFocus.",
            "/focus",
            value(focus, :source, "LearningFocus")
          )
        end)

      [current_action | next_actions]
    else
      []
    end
  end

  defp unhealthy_action(id, priority, status, title, reason, href, source) do
    normalized_status = normalized(status)

    if normalized_status not in [nil, "", "UNKNOWN", "NOT_CONFIGURED"] and
         normalized_status not in @positive do
      action(id, priority, title, reason <> " Current state: #{normalized_status}.", href, source)
    end
  end

  defp action(id, priority, title, reason, href, source) do
    %{
      id: id,
      priority: priority,
      title: title,
      reason: reason,
      href: href,
      source: source
    }
  end

  defp unavailable_mission(reason) do
    %{
      status: "UNAVAILABLE",
      title: "No verified mission configured",
      objective: nil,
      current: nil,
      instruction: nil,
      done_when: nil,
      context: nil,
      source: "LearningFocus",
      reason: reason
    }
  end

  defp nested(map, [key], default), do: value(map, key, default)

  defp nested(map, [key | rest], default) do
    case value(map, key) do
      nested_map when is_map(nested_map) -> nested(nested_map, rest, default)
      _ -> default
    end
  end

  defp nested(map, keys), do: nested(map, keys, nil)

  defp value(map, key, default \\ nil)

  defp value(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, to_string(key), default))

  defp value(_map, _key, default), do: default

  defp normalized(nil), do: nil
  defp normalized(value), do: value |> to_string() |> String.upcase()
end
