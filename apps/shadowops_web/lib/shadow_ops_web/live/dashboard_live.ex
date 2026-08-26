defmodule ShadowOpsWeb.DashboardLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents

  alias ShadowOpsApi
  alias ShadowOpsCore.{DailyControl, JobQueue, LearningFocus, Status}
  alias ShadowOpsWeb.{IntegrationCatalog, MissionBrief, ProjectDomains, RuntimeOverview}

  @refresh_ms 15_000

  @source_order ~w(system security audit ihk evidence career knowledge services social)

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

      <.panel title="Daily control" description="One-click workflows for daily operations.">
        <div class="mc-command-grid">
          <a class="mc-command-card" href="/daily-control">
            <span class="mc-command-kicker">Control</span>
            <strong>Daily Control</strong>
            <span>Full system status overview and prioritized actions</span>
          </a>
          <a class="mc-command-card" href="/workflows/so:wf:v1:system-doctor">
            <span class="mc-command-kicker">Diagnostic</span>
            <strong>System Doctor</strong>
            <span>Health check and automated remediation</span>
          </a>
          <a class="mc-command-card" href="/workflows/so:wf:v1:release-acceptance">
            <span class="mc-command-kicker">Release</span>
            <strong>Release Acceptance</strong>
            <span>Pre-deployment verification and quality gate</span>
          </a>
          <a class="mc-command-card" href="/projects/ihk">
            <span class="mc-command-kicker">IHK</span>
            <strong>IHK Evidence Gate</strong>
            <span>Verify and archive project evidence artifacts</span>
          </a>
          <a class="mc-command-card" href="/career">
            <span class="mc-command-kicker">Career</span>
            <strong>Career Control</strong>
            <span>Career pipeline status and next steps</span>
          </a>
        </div>
      </.panel>
    </.app_shell>
    """
  end

  defp source_card(assigns) do
    ~H"""
    <a class="mc-card-link" href={@card.href}>
      <.metric_card
        label={@card.label}
        value={@card.value}
        status={@card.status}
        source={@card.source}
        note={@card.note}
      />
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
    attention_items = build_attention_items(source_cards, daily)

    assign(socket,
      overview: overview,
      source_cards: source_cards,
      attention_items: attention_items,
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

    DailyControl.build(normalized, ihk)
  end

  defp build_source_cards(overview, ihk) do
    cards =
      [
        source_card_data("system", "System", overview.readiness.state, "runtime readiness",
          note: "Required dependencies and audit readiness",
          href: "/infrastructure"
        ),
        source_card_data(
          "security",
          "Security",
          overview.security.overall,
          overview.security.source,
          note: "Governance and write-boundary state",
          href: "/security"
        ),
        source_card_data("audit", "Audit", overview.audit.state, overview.audit.source,
          note: "Chain integrity and verification",
          href: "/audit"
        ),
        source_card_data("ihk", "IHK", ihk.status, "project domains",
          note: ihk.summary || "Zero Trust project source truth",
          href: "/projects/ihk"
        ),
        source_card_data(
          "evidence",
          "Evidence",
          source_value(Map.get(overview, :evidence, %{}), :status, "UNKNOWN"),
          "local filesystem",
          note: "#{source_value(Map.get(overview, :evidence, %{}), :record_count, 0)} artifacts",
          href: "/evidence"
        ),
        source_card_data(
          "career",
          "Career",
          source_value(Map.get(overview, :career, %{}), :status, "UNKNOWN"),
          "career source",
          note: "#{source_value(Map.get(overview, :career, %{}), :record_count, 0)} records",
          href: "/career"
        ),
        source_card_data(
          "knowledge",
          "Knowledge",
          source_value(Map.get(overview, :knowledge, %{}), :status, "UNKNOWN"),
          source_value(Map.get(overview, :knowledge, %{}), :source, "knowledge source"),
          note: knowledge_note(Map.get(overview, :knowledge, %{})),
          href: "/knowledge"
        ),
        source_card_data(
          "services",
          "Services",
          service_overall_status(overview),
          source_value(Map.get(overview, :services, %{}), :source, "runtime services"),
          note: service_note(overview),
          href: "/services"
        ),
        source_card_data(
          "social",
          "Social",
          social_status(Map.get(overview, :social, %{})),
          Map.get(Map.get(overview, :social, %{}), :source, "social sources"),
          note: social_note(Map.get(overview, :social, %{})),
          href: "/social"
        )
      ]

    Enum.sort_by(cards, fn card ->
      Enum.find_index(@source_order, &(&1 == card.id)) || 99
    end)
  end

  defp source_card_data(id, label, status, source, opts) do
    %{
      id: id,
      label: label,
      value: Status.normalize(status),
      status: status,
      source: source,
      note: opts[:note],
      href: opts[:href]
    }
  end

  defp build_attention_items(cards, daily) do
    card_items =
      cards
      |> Enum.filter(&attention_needed?/1)
      |> Enum.map(fn card ->
        %{
          label: card.label,
          status: card.status,
          detail: card.note || "#{card.label} source requires attention"
        }
      end)

    daily_items =
      daily.checks
      |> Enum.reject(&(&1.status == "GREEN"))
      |> Enum.map(fn check ->
        %{
          label: check.domain,
          status: check.status,
          detail: check.summary
        }
      end)

    merged =
      (card_items ++ daily_items)
      |> Enum.uniq_by(&{&1.label, &1.status})
      |> Enum.sort_by(fn item -> severity_sort_key(item.status) end)

    Enum.take(merged, 6)
  end

  defp attention_needed?(%{status: status}) when status in ["READY", "HEALTHY", "VERIFIED"],
    do: false

  defp attention_needed?(%{status: "NOT_CONFIGURED"}), do: false
  defp attention_needed?(_), do: true

  defp severity_sort_key("BLOCKED"), do: 0
  defp severity_sort_key("UNAVAILABLE"), do: 1
  defp severity_sort_key("DEGRADED"), do: 2
  defp severity_sort_key("ATTENTION"), do: 3
  defp severity_sort_key("GREEN"), do: 99
  defp severity_sort_key(_), do: 50

  defp knowledge_note(knowledge) do
    count = source_value(knowledge, :record_count, 0)
    availability = source_value(knowledge, :availability, "UNKNOWN")

    cond do
      is_integer(count) and count > 0 -> "#{count} sources, #{availability}"
      availability == "AVAILABLE" -> "Connected, count unavailable"
      true -> "Source #{String.downcase(availability)}"
    end
  end

  defp service_overall_status(overview) do
    services = Map.get(overview.services, :services, [])
    ready = Enum.count(services, &(record_value(&1, :status, "") == "READY"))

    cond do
      services == [] -> "UNAVAILABLE"
      ready == length(services) -> "READY"
      ready > 0 -> "MIXED"
      true -> "UNAVAILABLE"
    end
  end

  defp service_note(overview) do
    services = Map.get(overview.services, :services, [])
    ready = Enum.count(services, &(record_value(&1, :status, "") == "READY"))
    "#{ready}/#{length(services)} ready"
  end

  defp social_status(%{status: status}), do: status
  defp social_status(_), do: "UNAVAILABLE"

  defp social_note(%{source: source}) when is_binary(source), do: source
  defp social_note(%{error_message: msg}) when is_binary(msg), do: msg
  defp social_note(_), do: "Social source"

  defp source_value(%_{} = struct, key, default) when is_atom(key),
    do: Map.get(struct, key, default)

  defp source_value(source, key, default) when is_map(source) and is_atom(key) do
    Map.get(source, key, Map.get(source, Atom.to_string(key), default))
  end

  defp source_value(_source, _key, default), do: default

  defp record_value(record, key, default) when is_map(record),
    do: Map.get(record, key, Map.get(record, to_string(key), default))

  defp record_value(_record, _key, default), do: default

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
