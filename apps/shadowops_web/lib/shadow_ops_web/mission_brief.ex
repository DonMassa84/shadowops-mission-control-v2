defmodule ShadowOpsWeb.MissionBrief do
  @moduledoc "Deterministic mission and next-action projection from verified ShadowOps state."

  @positive ~w(READY ONLINE CONNECTED AVAILABLE)

  def build(overview, jobs, integrations, focus)
      when is_map(overview) and is_map(jobs) and is_map(integrations) and is_map(focus) do
    %{
      mission: mission(focus, overview),
      actions:
        overview
        |> action_candidates(jobs, integrations, focus)
        |> Enum.sort_by(& &1.rank)
        |> Enum.take(3)
    }
  end

  defp mission(
         %{"availability" => "AVAILABLE", "goal" => goal, "current" => current} = focus,
         _overview
       )
       when is_map(goal) and is_map(current) do
    %{
      title: value(goal, "title", "Configured mission"),
      current: value(current, "title", "Configured focus"),
      detail: value(current, "instruction", value(goal, "smart", "Configured mission")),
      done_when: value(current, "done_when", "Defined by configured focus"),
      source: value(focus, "source", "LEARNING_FOCUS"),
      status: "READY"
    }
  end

  defp mission(_focus, overview) do
    state = get_in(overview, [:readiness, :state]) || "UNAVAILABLE"

    %{
      title: "Restore operational readiness",
      current: "Runtime readiness is #{state}",
      detail: "No verified configured mission is available; only runtime readiness is projected.",
      done_when: "Runtime readiness is READY and a configured mission source is available.",
      source: "runtime readiness",
      status: state
    }
  end

  defp action_candidates(overview, jobs, integrations, focus) do
    []
    |> add_approvals(overview)
    |> add_readiness(overview)
    |> add_integrations(integrations)
    |> add_services(overview)
    |> add_compute(overview)
    |> add_jobs(jobs)
    |> add_focus(focus)
  end

  defp add_approvals(actions, overview) do
    records = get_in(overview, [:approvals, :records]) || []
    count = Enum.count(records, &(record_value(&1, :status, "") == "PENDING"))

    if count > 0 do
      [
        action(
          10,
          "Review pending approvals",
          "#{count} governed action(s) are waiting for an operator decision.",
          "/approvals",
          get_in(overview, [:approvals, :source]) || "approval store",
          "DEGRADED"
        )
        | actions
      ]
    else
      actions
    end
  end

  defp add_readiness(actions, overview) do
    state = get_in(overview, [:readiness, :state]) || "UNAVAILABLE"

    if state == "READY" do
      actions
    else
      [
        action(
          20,
          "Restore runtime readiness",
          "Required runtime dependencies are #{state}.",
          "/infrastructure",
          "runtime readiness",
          state
        )
        | actions
      ]
    end
  end

  defp add_integrations(actions, integrations) do
    status = value(integrations, :status, "UNAVAILABLE")

    if status == "READY" do
      actions
    else
      required_ready = value(integrations, :required_core_ready_count, 0)
      required_total = value(integrations, :required_core_count, 0)

      [
        action(
          30,
          "Repair required integrations",
          "Required core sources ready: #{required_ready}/#{required_total}.",
          "/integrations",
          value(integrations, :source, "integration catalog"),
          status
        )
        | actions
      ]
    end
  end

  defp add_services(actions, overview) do
    services = get_in(overview, [:services, :services]) || []
    ready = Enum.count(services, &(record_value(&1, :status, "") == "READY"))
    total = length(services)

    if total > 0 and ready < total do
      [
        action(
          40,
          "Review degraded services",
          "Runtime services ready: #{ready}/#{total}.",
          "/services",
          get_in(overview, [:services, :source]) || "runtime services",
          if(ready > 0, do: "DEGRADED", else: "UNAVAILABLE")
        )
        | actions
      ]
    else
      actions
    end
  end

  defp add_compute(actions, overview) do
    nodes =
      overview
      |> get_in([:nodes, :records])
      |> List.wrap()
      |> Enum.reject(&(get_in(&1, [:metadata, :logical]) == true))

    ready = Enum.count(nodes, &(record_value(&1, :status, "") in ["READY", "ONLINE"]))
    total = length(nodes)

    if total > 0 and ready < total do
      [
        action(
          50,
          "Check physical compute",
          "Physical nodes ready: #{ready}/#{total}.",
          "/compute",
          get_in(overview, [:nodes, :source]) || "node catalog",
          if(ready > 0, do: "DEGRADED", else: "UNAVAILABLE")
        )
        | actions
      ]
    else
      actions
    end
  end

  defp add_jobs(actions, jobs) do
    status = value(jobs, :status, "UNAVAILABLE")

    if status in @positive do
      actions
    else
      [
        action(
          60,
          "Review workload queue",
          value(jobs, :error_message, "Persistent job queue is not ready."),
          "/jobs",
          value(jobs, :source, "job queue"),
          status
        )
        | actions
      ]
    end
  end

  defp add_focus(actions, %{"availability" => "AVAILABLE"} = focus) do
    current = value(focus, "current", %{})

    configured =
      [
        action(
          70,
          value(current, "title", "Execute configured focus"),
          value(current, "instruction", "Follow the configured focus plan."),
          "/focus",
          value(focus, "source", "LEARNING_FOCUS"),
          "READY"
        )
      ] ++
        (focus
         |> value("next", [])
         |> Enum.filter(&is_binary/1)
         |> Enum.take(2)
         |> Enum.with_index(1)
         |> Enum.map(fn {title, index} ->
           action(
             70 + index,
             title,
             "Configured next action from the active focus plan.",
             "/focus",
             value(focus, "source", "LEARNING_FOCUS"),
             "READY"
           )
         end))

    configured ++ actions
  end

  defp add_focus(actions, _focus), do: actions

  defp action(rank, title, detail, href, source, status) do
    %{rank: rank, title: title, detail: detail, href: href, source: source, status: status}
  end

  defp value(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, to_string(key), default))

  defp value(_map, _key, default), do: default

  defp record_value(record, key, default) when is_map(record),
    do: Map.get(record, key, Map.get(record, to_string(key), default))

  defp record_value(_record, _key, default), do: default
end
