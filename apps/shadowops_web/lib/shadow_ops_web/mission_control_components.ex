defmodule ShadowOpsWeb.MissionControlComponents do
  @moduledoc "Reusable, accessible Mission Control UI components."
  use Phoenix.Component

  alias ShadowOpsCore.Status

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
          <span class="mc-brand-mark" aria-hidden="true">
            <img src="/assets/shadowops-mark.svg" alt="" />
          </span>
          <span><strong>ShadowOps</strong><small>Mission Control</small></span>
        </a>
        <nav>
          <.nav_group label="Dashboard" items={[{"Overview", "/"}]} active={@active} />
          <.nav_group
            label="Operations"
            items={[
              {"Compute", "/compute"},
              {"Workflows", "/workflows"},
              {"Runs", "/runs"},
              {"Jobs", "/jobs"},
              {"Services", "/services"},
              {"Backups", "/backups"}
            ]}
            active={@active}
          />
          <.nav_group
            label="Sources"
            items={[
              {"Integrations", "/integrations"},
              {"Evidence", "/evidence"},
              {"Knowledge", "/knowledge"}
            ]}
            active={@active}
          />
          <.nav_group
            label="Governance"
            items={[
              {"Approvals", "/approvals"},
              {"Security", "/security"},
              {"Audit", "/audit"},
              {"Logs", "/logs"}
            ]}
            active={@active}
          />
          <.nav_group
            label="Focus & AI"
            items={[
              {"Focus", "/focus"},
              {"AI", "/ai"},
              {"Agents", "/agents"}
            ]}
            active={@active}
          />
        </nav>
        <div class="mc-sidebar-footer">
          <span class="mc-operator-avatar">SO</span>
          <span><strong>Local operator</strong><small>Remote AI · WebMCP</small></span>
        </div>
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
            <a class="mc-icon-button" href={@active} aria-label="Refresh current view" title="Refresh">↻</a>
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
      <a :for={{label, path} <- @items} href={path} class={if active?(@active, path), do: "is-active"} aria-current={if active?(@active, path), do: "page"}>
        <span class="mc-nav-icon" aria-hidden="true">{nav_icon(label)}</span>
        <span>{label}</span>
      </a>
    </section>
    """
  end

  attr(:status, :any, required: true)
  attr(:label, :string, default: nil)

  def status_badge(assigns) do
    value = Status.normalize(assigns.status)
    assigns = assigns |> assign(:value, value) |> assign(:tone, Status.tone(value))

    ~H"""
    <span class={["mc-badge", "is-#{@tone}"]}><span aria-hidden="true"></span>{@label || @value}</span>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :any, required: true)
  attr(:status, :any, default: "AVAILABLE")
  attr(:source, :string, default: nil)
  attr(:note, :string, default: nil)
  attr(:icon, :string, default: nil)

  def metric_card(assigns) do
    assigns = assign(assigns, :resolved_icon, assigns.icon || metric_icon(assigns.label))

    ~H"""
    <article class="mc-metric">
      <div class="mc-metric-head">
        <span class="mc-metric-label">
          <span class="mc-metric-icon" aria-hidden="true">{@resolved_icon}</span>
          <span>{@label}</span>
        </span>
        <.status_badge status={@status} />
      </div>
      <strong>{@value}</strong>
      <p :if={@note}>{@note}</p>
      <small :if={@source}>Source: {@source}</small>
      <span class="mc-metric-spark" aria-hidden="true"></span>
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

  defp nav_icon("Overview"), do: "⌂"
  defp nav_icon("Compute"), do: "▦"
  defp nav_icon("Workflows"), do: "⌘"
  defp nav_icon("Runs"), do: "▷"
  defp nav_icon("Jobs"), do: "◫"
  defp nav_icon("Services"), do: "◆"
  defp nav_icon("Backups"), do: "▱"
  defp nav_icon("Integrations"), do: "◎"
  defp nav_icon("Evidence"), do: "▤"
  defp nav_icon("Knowledge"), do: "▥"
  defp nav_icon("Approvals"), do: "✓"
  defp nav_icon("Security"), do: "◇"
  defp nav_icon("Audit"), do: "▧"
  defp nav_icon("Logs"), do: "▰"
  defp nav_icon("Focus"), do: "◉"
  defp nav_icon("AI"), do: "✦"
  defp nav_icon("Agents"), do: "⌬"
  defp nav_icon(_), do: "·"

  defp metric_icon(label) do
    case String.downcase(to_string(label)) do
      "system" -> "◇"
      "compute" -> "▦"
      "physical nodes" -> "▣"
      "reachable" -> "●"
      "job queue" -> "◫"
      "visible jobs" -> "◫"
      "workflows" -> "⌘"
      "runs" -> "▷"
      "pending approvals" -> "✓"
      "nodes" -> "▣"
      "services" -> "◆"
      "ai policy" -> "✦"
      "security" -> "◇"
      "audit" -> "▧"
      "backup" -> "▱"
      "evidence" -> "▤"
      "knowledge" -> "▥"
      "integrations" -> "◎"
      "focus" -> "◉"
      _ -> "◆"
    end
  end

  defp active?(active, "/"), do: active == "/"
  defp active?(active, path), do: active == path or String.starts_with?(active, path <> "/")
end
