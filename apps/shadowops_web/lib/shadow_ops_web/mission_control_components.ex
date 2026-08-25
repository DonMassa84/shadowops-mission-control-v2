defmodule ShadowOpsWeb.MissionControlComponents do
  @moduledoc "Reusable, accessible Mission Control UI components."
  use Phoenix.Component

  attr(:title, :string, required: true)
  attr(:subtitle, :string, default: nil)
  attr(:active, :string, required: true)
  attr(:availability, :string, default: "AVAILABLE")
  attr(:updated_at, :string, default: nil)
  slot(:inner_block, required: true)

  def app_shell(assigns) do
    ~H"""
    <div class="mc-shell">
      <link rel="stylesheet" href="/assets/mission-control.css" />
      <link rel="icon" type="image/svg+xml" href="/assets/shadowops-mark.svg" />
      <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
      <script type="module" src="/assets/mission-control.js"></script>
      <a class="mc-skip" href="#mission-content">Skip to content</a>
      <aside class="mc-sidebar" aria-label="Mission Control navigation">
        <a class="mc-brand" href="/" aria-label="ShadowOps dashboard">
          <span class="mc-brand-mark">SO</span>
          <span><strong>ShadowOps</strong><small>Mission Control</small></span>
        </a>
        <nav>
          <.nav_group label="Dashboard" items={[{"Overview", "/"}, {"Layer Health", "/layers"}]} active={@active} />
          <.nav_group label="Operations" items={[{"Infrastructure", "/infrastructure"}, {"Workflows", "/workflows"}, {"Runs", "/runs"}, {"Services", "/services"}, {"Nodes", "/nodes"}, {"Backups", "/backups"}]} active={@active} />
          <.nav_group label="Projects" items={[{"Overview", "/projects"}, {"Finance", "/projects/finance"}, {"Investigations", "/projects/investigations"}, {"IHK", "/projects/ihk"}, {"Community", "/projects/community"}]} active={@active} />
          <.nav_group label="Intelligence" items={[{"Agents", "/agents"}, {"AI", "/ai"}, {"Knowledge", "/knowledge"}, {"Career", "/career"}, {"Reporting", "/reporting"}]} active={@active} />
          <.nav_group label="Social" items={[{"Overview", "/social"}, {"Facebook", "/social/facebook"}, {"Social Review", "/social/review"}, {"Messenger", "/social/messenger"}, {"WhatsApp", "/social/whatsapp"}, {"Telegram", "/social/telegram"}]} active={@active} />
          <.nav_group label="Governance" items={[{"Approvals", "/approvals"}, {"Security", "/security"}, {"Audit", "/audit"}, {"Evidence", "/evidence"}, {"Legal", "/legal"}, {"Logs", "/logs"}]} active={@active} />
          <.nav_group label="System" items={[{"i7 Display", "/display/i7"}, {"Health", "/health"}, {"Readiness", "/ready"}]} active={@active} />
        </nav>
      </aside>
      <div class="mc-workspace">
        <header class="mc-topbar">
          <div>
            <p class="mc-kicker">ShadowOps / Local control plane</p>
            <h1>{@title}</h1>
            <p :if={@subtitle} class="mc-subtitle">{@subtitle}</p>
          </div>
          <div class="mc-topbar-meta">
            <.status_badge status={@availability} />
            <span :if={@updated_at} class="mc-updated">Updated <time>{@updated_at}</time></span>
          </div>
        </header>
        <main id="mission-content" class="mc-main" tabindex="-1">
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:items, :list, required: true)
  attr(:active, :string, required: true)

  defp nav_group(assigns) do
    ~H"""
    <section class="mc-nav-group">
      <h2>{@label}</h2>
      <a :for={{label, path} <- @items} href={path} class={if active?(@active, path), do: "is-active"} aria-current={if active?(@active, path), do: "page"}>{label}</a>
    </section>
    """
  end

  attr(:status, :any, required: true)
  attr(:label, :string, default: nil)

  def status_badge(assigns) do
    value = normalize(assigns.status)
    assigns = assigns |> assign(:value, value) |> assign(:tone, tone(value))

    ~H"""
    <span class={["mc-badge", "is-#{@tone}"]}><span aria-hidden="true"></span>{@label || @value}</span>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :any, required: true)
  attr(:status, :any, default: "AVAILABLE")
  attr(:source, :string, default: nil)
  attr(:note, :string, default: nil)

  def metric_card(assigns) do
    ~H"""
    <article class="mc-metric">
      <div class="mc-metric-head"><span>{@label}</span><.status_badge status={@status} /></div>
      <strong>{@value}</strong>
      <p :if={@note}>{@note}</p>
      <small :if={@source}>Source: {@source}</small>
    </article>
    """
  end

  attr(:title, :string, required: true)
  attr(:state, :string, default: "NOT_CONNECTED")
  attr(:reason, :string, required: true)
  attr(:source, :string, default: nil)

  def unavailable_state(assigns) do
    ~H"""
    <section class="mc-unavailable" role="status">
      <.status_badge status={@state} />
      <div><h2>{@title}</h2><p>{@reason}</p><small :if={@source}>Required source: {@source}</small></div>
    </section>
    """
  end

  attr(:source, :string, required: true)
  attr(:updated_at, :string, default: nil)
  attr(:availability, :string, default: "AVAILABLE")

  def source_meta(assigns) do
    ~H"""
    <div class="mc-source-meta">
      <span>Source: <strong>{@source}</strong></span>
      <span :if={@updated_at}>Updated: <time>{@updated_at}</time></span>
      <.status_badge status={@availability} />
    </div>
    """
  end

  attr(:title, :string, required: true)
  attr(:description, :string, default: nil)
  slot(:actions)
  slot(:inner_block, required: true)

  def panel(assigns) do
    ~H"""
    <section class="mc-panel">
      <header class="mc-panel-head"><div><h2>{@title}</h2><p :if={@description}>{@description}</p></div><div :if={@actions != []} class="mc-actions">{render_slot(@actions)}</div></header>
      {render_slot(@inner_block)}
    </section>
    """
  end

  defp active?(active, "/"), do: active == "/"
  defp active?(active, path), do: active == path or String.starts_with?(active, path <> "/")
  defp normalize(value) when is_atom(value), do: value |> Atom.to_string() |> String.upcase()
  defp normalize(value) when is_binary(value), do: String.upcase(value)
  defp normalize(value), do: to_string(value) |> String.upcase()

  defp tone(value) do
    cond do
      value in ~w(PASS VALID AVAILABLE CONNECTED ONLINE SUCCESS APPROVED READY VERIFIED HEALTHY ACTIVE EXCELLENT) ->
        "success"

      value in ~w(FAIL INVALID ERROR OFFLINE FAILED REJECTED BLOCKED BLOCKED_CONFIGURATION CRITICAL) ->
        "error"

      value in ~w(PENDING RUNNING QUEUED DEGRADED PARTIAL REVIEW WARN WARNING) ->
        "review"

      value in ~w(NOT_ASSESSED NOT_CONFIGURED NOT_CONNECTED UNAVAILABLE UNKNOWN NOT_CHECKED EXPIRED DISABLED DISABLED_BY_CONFIGURATION) ->
        "muted"

      true ->
        "neutral"
    end
  end
end
