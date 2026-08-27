defmodule ShadowOpsWeb.DashboardLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents

  alias ShadowOpsApi
  alias ShadowOpsCore.{DailyControl, JobQueue, LearningFocus, Status}
  alias ShadowOpsWeb.{IntegrationCatalog, MissionBrief, ProjectDomains, RuntimeOverview}
  alias WorkflowEngine.WorkflowIds

  @refresh_ms 15_000

  @source_order ~w(system security audit ihk evidence knowledge services social career backups)
  @one_click_targets [
    %{key: "daily_control", label: "Daily Control", kind: "Control", route: "/daily-control"},
    %{key: "system_doctor", label: "System Doctor", kind: "Diagnostic"},
    %{key: "ihk_evidence_gate", label: "IHK Evidence Gate", kind: "IHK"},
    %{key: "release_acceptance", label: "Release Acceptance", kind: "Release"},
    %{key: "career_control", label: "Career Control", kind: "Career"}
  ]

  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_ms)
    {:ok, load(socket)}
  end

  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, load(socket)}
  end

  def render(assigns) do
    ~H"""
    <.app_shell
      title="Mission Control"
      subtitle="Source Truth · Current Mission · Attention Required · Next Actions"
      active="/"
      availability={@overview.readiness.state}
      updated_at={@updated_at}
    >
      <section class="mc-grid" aria-label="Source truth overview">
        <.source_card :for={card <- @source_cards} card={card} />
      </section>

      <.panel title="Current mission" description="Configured mission source; never synthesized from an AI guess.">
        <div class="mc-command-grid">
          <article class="mc-command-card">
            <span class="mc-command-kicker">Mission</span>
            <strong>{@mission.mission.title}</strong>
            <span>{@mission.mission.current}</span>
          </article>
          <article class="mc-command-card">
            <span class="mc-command-kicker">Execute</span>
            <strong>{@mission.mission.detail}</strong>
            <span>Done when: {@mission.mission.done_when}</span>
          </article>
          <article class="mc-command-card">
            <span class="mc-command-kicker">Evidence</span>
            <strong>{@mission.mission.source}</strong>
            <span><.status_badge status={@mission.mission.status} /></span>
          </article>
        </div>
      </.panel>

      <.panel
        :if={@attention_items != []}
        title="Attention required"
        description="Sources requiring operator awareness. Color-coded by severity."
      >
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead>
              <tr>
                <th>Source</th>
                <th>Status</th>
                <th>Detail</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={item <- @attention_items}>
                <td><strong>{item.label}</strong></td>
                <td><.status_badge status={item.status} /></td>
                <td class="mc-muted">{item.detail}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <.panel title="Top 3 next actions" description="Deterministic priority: governance and runtime blockers first, configured focus second. No invented tasks.">
        <div class="mc-command-grid" :if={@daily.top_actions != []}>
          <article
            :for={{action, index} <- Enum.with_index(@daily.top_actions, 1)}
            class="mc-command-card"
            data-role="top-action"
          >
            <span class="mc-command-kicker">{index} · {action.severity}</span>
            <strong>{action.title}</strong>
            <span>{action.reason}</span>
            <small>Domain: {action.domain}</small>
          </article>
        </div>
        <div class="mc-command-grid" :if={@daily.top_actions == [] and @mission.actions != []}>
          <a
            :for={{action, index} <- Enum.with_index(@mission.actions, 1)}
            class="mc-command-card"
            data-role="top-action"
            href={action.href}
          >
            <span class="mc-command-kicker">{index} · {action.status}</span>
            <strong>{action.title}</strong>
            <span>{action.detail}</span>
            <small>Source: {action.source}</small>
          </a>
        </div>
        <p :if={@daily.top_actions == [] and @mission.actions == []} class="mc-empty">No evidence-backed next action is currently available.</p>
      </.panel>

      <.panel title="One-click control" description="Registry-backed controls only. Unregistered or non-executable targets remain fail-visible.">
        <div class="mc-command-grid">
          <a
            :for={control <- Enum.filter(@one_click_controls, & &1.href)}
            class="mc-command-card"
            href={control.href}
            data-role="one-click-control"
          >
            <span class="mc-command-kicker">{control.kind} · {control.status}</span>
            <strong>{control.label}</strong>
            <span>{control.workflow_id}</span>
            <small>{control.action_label}</small>
          </a>
          <article
            :for={control <- Enum.reject(@one_click_controls, & &1.href)}
            class="mc-command-card"
            data-role="one-click-unavailable"
          >
            <span class="mc-command-kicker">{control.kind} · {control.status}</span>
            <strong>{control.label}</strong>
            <span>{control.workflow_id || "No canonical workflow ID registered"}</span>
            <small>Execution unavailable</small>
          </article>
        </div>
      </.panel>
    </.app_shell>
    """
  end

  defp source_card(assigns) do
    ~H"""
    <a class="mc-card-link" href={@card.href}>
      <article class="mc-metric" data-source-id={@card.id}>
        <div class="mc-metric-head">
          <span class="mc-metric-label"><span>{@card.label}</span></span>
          <.status_badge status={@card.status} />
        </div>
        <strong>{@card.value}</strong>
        <p :if={@card.note}>{@card.note}</p>
        <dl>
          <div><dt>Health</dt><dd>{@card.health}</dd></div>
          <div><dt>Real data</dt><dd>{to_string(@card.real_data)}</dd></div>
          <div><dt>Synthetic</dt><dd>{to_string(@card.synthetic)}</dd></div>
          <div><dt>Reachable</dt><dd>{to_string(@card.reachable)}</dd></div>
          <div><dt>Record count</dt><dd>{@card.record_count}</dd></div>
          <div><dt>Source type</dt><dd>{@card.source_type}</dd></div>
        </dl>
        <p :if={@card.error} class="mc-muted">Reason: {@card.error}</p>
        <small>Source: {@card.source}</small>
      </article>
    </a>
    """
  end

  defp load(socket) do
    overview = RuntimeOverview.snapshot()
    jobs = JobQueue.snapshot()
    integrations = IntegrationCatalog.snapshot()
    {:ok, focus} = LearningFocus.load()
    mission = MissionBrief.build(overview, jobs, integrations, focus)

    ihk = ProjectDomains.snapshot(:ihk)

    source_cards = build_source_cards(overview, ihk)
    daily = build_daily_control(overview, ihk)
    attention_items = build_attention_items(daily)
    one_click_controls = build_one_click_controls()

    assign(socket,
      overview: overview,
      source_cards: source_cards,
      attention_items: attention_items,
      one_click_controls: one_click_controls,
      mission: mission,
      daily: daily,
      updated_at: now()
    )
  end

  defp build_daily_control(overview, ihk) do
    normalized =
      overview
      |> Map.update(:approvals, [], fn
        %{records: records} when is_list(records) -> records
        records when is_list(records) -> records
        _ -> []
      end)
      |> Map.update(:runs, [], fn
        %{records: records} when is_list(records) -> records
        records when is_list(records) -> records
        _ -> []
      end)

    normalized
    |> DailyControl.build(ihk)
    |> Map.update!(:top_actions, &Enum.take(&1, 3))
  end

  defp build_source_cards(overview, ihk) do
    evidence = Map.get(overview, :evidence, %{})

    cards =
      [
        source_card_data("system", "System", Map.get(overview, :system, %{}),
          status: overview.readiness.state,
          source: "runtime readiness",
          note: "Required dependencies and audit readiness",
          href: "/infrastructure"
        ),
        source_card_data("security", "Security", Map.get(overview, :security, %{}),
          status: source_value(Map.get(overview, :security, %{}), :overall, "UNKNOWN"),
          note: "Governance and write-boundary state",
          href: "/security"
        ),
        source_card_data("audit", "Audit", Map.get(overview, :audit, %{}),
          status: source_value(Map.get(overview, :audit, %{}), :state, "UNKNOWN"),
          note: "Chain integrity and verification",
          href: "/audit"
        ),
        source_card_data("ihk", "IHK", ihk,
          source: "project domains",
          note: source_value(ihk, :summary, "Zero Trust project source truth"),
          href: "/projects/ihk"
        ),
        source_card_data("evidence", "Evidence", evidence,
          source: "local filesystem evidence adapter",
          note: evidence_note(evidence),
          href: "/evidence"
        ),
        source_card_data("knowledge", "Knowledge", Map.get(overview, :knowledge, %{}),
          note: knowledge_note(Map.get(overview, :knowledge, %{})),
          href: "/knowledge"
        ),
        source_card_data("services", "Services", Map.get(overview, :services, %{}),
          note: service_note(overview),
          href: "/services"
        ),
        source_card_data("social", "Social", Map.get(overview, :social, %{}),
          note: social_note(Map.get(overview, :social, %{})),
          href: "/social"
        ),
        source_card_data("career", "Career", Map.get(overview, :career, %{}),
          source: "career source adapter",
          note:
            "#{source_value(Map.get(overview, :career, %{}), :record_count, "UNAVAILABLE")} records",
          href: "/career"
        ),
        source_card_data("backups", "Backups", Map.get(overview, :backups, %{}),
          source: "bounded backup inventory",
          note: "Backup source truth",
          href: "/backups"
        )
      ]

    Enum.sort_by(cards, fn card ->
      Enum.find_index(@source_order, &(&1 == card.id)) || 99
    end)
  end

  defp source_card_data(id, label, payload, opts) do
    status = opts[:status] || truth_status(payload)
    source = opts[:source] || source_value(payload, :source, "canonical source")
    error = source_value(payload, :error_message, source_value(payload, :reason, nil))

    %{
      id: id,
      label: label,
      value: Status.normalize(status),
      status: status,
      health: source_value(payload, :health, "UNKNOWN"),
      real_data: source_value(payload, :real_data, false) == true,
      synthetic: source_value(payload, :synthetic, false) == true,
      reachable: source_value(payload, :reachable, false) == true,
      record_count: source_value(payload, :record_count, "UNAVAILABLE"),
      source_type: source_value(payload, :source_type, "INTERNAL"),
      source: public_text(source, "canonical source"),
      error: public_text(error, "Source detail unavailable"),
      note: public_text(opts[:note], "Source detail unavailable"),
      href: opts[:href]
    }
  end

  defp build_attention_items(daily) do
    daily.checks
    |> Enum.reject(&(&1.status == "GREEN"))
    |> Enum.map(fn check ->
      %{
        label: check.domain,
        status: attention_status(check),
        detail: "#{check.status}: #{check.summary}"
      }
    end)
    |> Enum.take(6)
  end

  defp attention_status(%{severity: severity}) when severity in ["CRITICAL", "HIGH"],
    do: severity

  defp attention_status(%{status: status}), do: status

  defp build_one_click_controls do
    workflows =
      case ShadowOpsApi.list_workflows() do
        {:ok, records} -> records
        {:error, _reason} -> []
      end

    Enum.map(@one_click_targets, &one_click_control(&1, workflows))
  end

  defp one_click_control(target, workflows) do
    workflow = Enum.find(workflows, &(Map.get(&1, "id") == target.key))

    canonical_id =
      case WorkflowIds.canonical_id(target.key) do
        {:ok, id} -> id
        {:error, _reason} -> nil
      end

    cond do
      is_nil(workflow) or is_nil(canonical_id) ->
        Map.merge(target, %{
          workflow_id: canonical_id,
          status: "NOT_CONFIGURED",
          href: nil,
          action_label: nil
        })

      Map.get(workflow, "read_only") == true and is_binary(target[:route]) ->
        Map.merge(target, %{
          workflow_id: canonical_id,
          status: "REGISTERED_READ_ONLY",
          href: target.route,
          action_label: "Open read-only control"
        })

      Map.get(workflow, "executable") == true ->
        Map.merge(target, %{
          workflow_id: canonical_id,
          status: "EXECUTABLE",
          href: "/workflows/#{target.key}",
          action_label: "Review / run through governed execution"
        })

      true ->
        Map.merge(target, %{
          workflow_id: canonical_id,
          status: Map.get(workflow, "execution_status", "UNAVAILABLE"),
          href: nil,
          action_label: nil
        })
    end
  end

  defp truth_status(payload) do
    source_value(payload, :status, nil) || source_value(payload, :state, nil) ||
      source_value(payload, :overall, nil) || source_value(payload, :availability, "UNKNOWN")
  end

  defp evidence_note(evidence) do
    artifacts = source_value(evidence, :artifacts, [])

    available =
      Enum.count(artifacts, &(source_value(&1, :verification_status, "") == "AVAILABLE"))

    verified = Enum.count(artifacts, &(source_value(&1, :verification_status, "") == "VERIFIED"))
    status = truth_status(evidence)

    "Source status: #{status} · Artifacts available: #{available} · Artifacts verified: #{verified}"
  end

  defp knowledge_note(knowledge) do
    sources = source_value(knowledge, :sources, [])
    complete = source_value(knowledge, :source_measurement_complete, false) == true
    availability = source_value(knowledge, :availability, "UNKNOWN")

    cond do
      complete -> "#{length(sources)} measured sources · #{availability}"
      true -> "Source #{String.downcase(availability)}"
    end
  end

  defp service_note(overview) do
    services = Map.get(overview.services, :services, [])
    ready = Enum.count(services, &(record_value(&1, :status, "") == "READY"))
    "#{ready}/#{length(services)} ready"
  end

  defp social_note(%{source: source}) when is_binary(source), do: source
  defp social_note(%{error_message: msg}) when is_binary(msg), do: msg
  defp social_note(_), do: "Social source"

  defp source_value(%_{} = struct, key, default) when is_atom(key),
    do: Map.get(struct, key, default)

  defp source_value(source, key, default) when is_map(source) and is_atom(key) do
    Map.get(source, key, Map.get(source, Atom.to_string(key), default))
  end

  defp source_value(_source, _key, default), do: default

  defp public_text(nil, _fallback), do: nil

  defp public_text(value, fallback) when is_binary(value) do
    if String.starts_with?(value, "/") or
         String.contains?(value, ["/home/", "/tmp/", "\\home\\"]),
       do: fallback,
       else: value
  end

  defp public_text(_value, fallback), do: fallback

  defp record_value(record, key, default) when is_map(record),
    do: Map.get(record, key, Map.get(record, to_string(key), default))

  defp record_value(_record, _key, default), do: default

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
