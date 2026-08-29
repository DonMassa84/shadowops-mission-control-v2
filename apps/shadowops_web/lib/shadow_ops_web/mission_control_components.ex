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
          <.nav_group label="Command" items={command_items()} active={@active} />
          <.nav_group label="Operations" items={operations_items()} active={@active} />
          <.nav_group label="Intelligence" items={intelligence_items()} active={@active} />
          <.nav_group label="Projects" items={projects_items()} active={@active} />
          <.nav_group label="Social" items={social_items()} active={@active} />
          <.nav_group label="Governance" items={governance_items()} active={@active} />
          <.nav_group label="System" items={system_items()} active={@active} />
        </nav>
        <div class="mc-sidebar-footer">
          <span class="mc-operator-avatar">SO</span>
          <span><strong>Local operator</strong><small>Administrator</small></span>
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

  defp command_items do
    [
      {"Overview", "/"},
      {"Attention", "/attention"},
      {"Integrations", "/integrations"}
    ]
  end

  defp operations_items do
    [
      {"Infrastructure", "/infrastructure"},
      {"Compute", "/compute"},
      {"Nodes", "/nodes"},
      {"Services", "/services"},
      {"Workflows", "/workflows"},
      {"Runs", "/runs"},
      {"Jobs", "/jobs"},
      {"Backups", "/backups"}
    ]
  end

  defp intelligence_items do
    [
      {"Agents", "/agents"},
      {"AI", "/ai"},
      {"Knowledge", "/knowledge"},
      {"Reporting", "/reporting"}
    ]
  end

  defp projects_items do
    [
      {"All Projects", "/projects"},
      {"Federated", "/projects/federated"},
      {"Career", "/projects/career"},
      {"IHK", "/projects/ihk"},
      {"Finance", "/projects/finance"},
      {"Investigations", "/projects/investigations"},
      {"Social", "/projects/social"},
      {"Knowledge", "/projects/knowledge"},
      {"ChatGPT", "/projects/chatgpt"},
      {"Housing", "/projects/housing"},
      {"Administration", "/projects/administration"},
      {"Health", "/projects/health"},
      {"Learning", "/projects/learning"},
      {"Personal Framework", "/projects/personal_framework"}
    ]
  end

  defp social_items do
    [
      {"Overview", "/social"},
      {"Facebook", "/social/facebook"},
      {"Messenger", "/social/messenger"},
      {"WhatsApp", "/social/whatsapp"},
      {"Telegram", "/social/telegram"}
    ]
  end

  defp governance_items do
    [
      {"Approvals", "/approvals"},
      {"Security", "/security"},
      {"Audit", "/audit"},
      {"Evidence", "/evidence"},
      {"Legal", "/legal"},
      {"Logs", "/logs"}
    ]
  end

  defp system_items do
    [
      {"Settings", "/settings"},
      {"Runtime Dashboard", "/runtime"},
      {"i7 Display", "/display/i7"},
      {"Health", "/health"},
      {"Readiness", "/ready"}
    ]
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
  attr(:evidence, :list, default: [])
  attr(:unlock_requirements, :list, default: [])

  def unavailable_state(assigns) do
    ~H"""
    <section class="mc-unavailable" role="status">
      <.status_badge status={@state} />
      <div>
        <h2>{@title}</h2>
        <p>{@reason}</p>
        <small :if={@source}>Required source: {@source}</small>
      </div>
      <div :if={@evidence != []} class="mc-evidence-list">
        <h3>Evidence</h3>
        <ul>
          <li :for={e <- @evidence}>
            <.status_badge status={e.result} />
            <span>{e.gate}: {e.evidence_ref}</span>
          </li>
        </ul>
      </div>
      <div :if={@unlock_requirements != []} class="mc-unlock-requirements">
        <h3>Unlock requirements</h3>
        <ul>
          <li :for={req <- @unlock_requirements}>{req}</li>
        </ul>
      </div>
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

  attr(:title, :string, required: true)
  attr(:state, :string, default: "UNKNOWN")
  attr(:mode, :string, default: "UNKNOWN")
  attr(:real_data, :boolean, default: false)
  attr(:reachable, :boolean, default: false)
  attr(:synthetic, :boolean, default: false)
  attr(:runtime, :string, default: nil)
  attr(:approval, :string, default: nil)
  attr(:evidence, :string, default: nil)
  attr(:last_probe, :string, default: nil)
  attr(:unlock_requirement, :string, default: nil)

  def capability_card(assigns) do
    assigns = assign(assigns, :computed_state_class, state_class(assigns.state))

    ~H"""
    <article class={"mc-capability-card {@computed_state_class}"}>
      <div class="mc-capability-head">
        <strong>{@title}</strong>
        <.status_badge status={@state} label={@mode} />
      </div>
      <div class="mc-capability-meta">
        <span :if={@real_data} class="mc-tag is-real">Real Data</span>
        <span :if={@reachable} class="mc-tag is-reachable">Reachable</span>
        <span :if={@synthetic} class="mc-tag is-synthetic">Synthetic</span>
        <span :if={@runtime} class="mc-tag">Runtime: {@runtime}</span>
        <span :if={@approval} class="mc-tag">Approval: {@approval}</span>
        <span :if={@evidence} class="mc-tag">Evidence: {@evidence}</span>
        <span :if={@last_probe} class="mc-tag">Last probe: {@last_probe}</span>
      </div>
      <p :if={@unlock_requirement} class="mc-unlock-hint">🔓 {@unlock_requirement}</p>
    </article>
    """
  end

  attr(:action_type, :string, required: true)
  attr(:risk, :string, required: true)
  attr(:state, :string, required: true)
  attr(:label, :string, required: true)
  attr(:href, :string, default: nil)
  attr(:disabled, :boolean, default: false)

  def action_button(assigns) do
    assigns = assign(assigns, :computed_action_class, action_class(assigns.action_type))
    assigns = assign(assigns, :computed_disabled, assigns.disabled)

    assigns =
      assign(assigns, :computed_is_disabled, if(assigns.disabled, do: "is-disabled", else: ""))

    ~H"""
    <a
      class={"mc-button {@computed_action_class} {@computed_is_disabled}"}
      href={@href}
      :if={!@computed_disabled && @href}
      aria-disabled={@computed_disabled}
    >
      {@label}
    </a>
    <button
      class={"mc-button {@computed_action_class} {@computed_is_disabled}"}
      :if={@computed_disabled}
      disabled
    >
      {@label}
      <span class="mc-tooltip">State: {@state} — Risk: {@risk}</span>
    </button>
    """
  end

  defp nav_icon("Overview"), do: "⌂"
  defp nav_icon("Attention"), do: "⚠"
  defp nav_icon("Integrations"), do: "◎"
  defp nav_icon("Infrastructure"), do: "▦"
  defp nav_icon("Compute"), do: "▣"
  defp nav_icon("Nodes"), do: "▣"
  defp nav_icon("Services"), do: "◆"
  defp nav_icon("Workflows"), do: "⌘"
  defp nav_icon("Runs"), do: "▷"
  defp nav_icon("Jobs"), do: "◫"
  defp nav_icon("Backups"), do: "▱"
  defp nav_icon("Agents"), do: "⌬"
  defp nav_icon("AI"), do: "✦"
  defp nav_icon("Knowledge"), do: "▥"
  defp nav_icon("Reporting"), do: "◰"
  defp nav_icon("All Projects"), do: "◎"
  defp nav_icon("Federated"), do: "◎"
  defp nav_icon("Career"), do: "◈"
  defp nav_icon("IHK"), do: "▤"
  defp nav_icon("Finance"), do: "◇"
  defp nav_icon("Investigations"), do: "⌕"
  defp nav_icon("Social"), do: "♢"
  defp nav_icon("ChatGPT"), do: "◌"
  defp nav_icon("Housing"), do: "⌂"
  defp nav_icon("Administration"), do: "⚙"
  defp nav_icon("Health"), do: "♥"
  defp nav_icon("Learning"), do: "◰"
  defp nav_icon("Personal Framework"), do: "▣"
  defp nav_icon("Facebook"), do: "f"
  defp nav_icon("Messenger"), do: "◍"
  defp nav_icon("WhatsApp"), do: "◉"
  defp nav_icon("Telegram"), do: "△"
  defp nav_icon("Approvals"), do: "✓"
  defp nav_icon("Security"), do: "◇"
  defp nav_icon("Audit"), do: "▧"
  defp nav_icon("Evidence"), do: "▤"
  defp nav_icon("Legal"), do: "§"
  defp nav_icon("Logs"), do: "▰"
  defp nav_icon("Settings"), do: "⚙"
  defp nav_icon("Runtime Dashboard"), do: "◉"
  defp nav_icon("i7 Display"), do: "▣"
  defp nav_icon("Readiness"), do: "●"
  defp nav_icon(_), do: "·"

  defp metric_icon(label) do
    case String.downcase(to_string(label)) do
      "ryzen" -> "◆"
      "i7" -> "◇"
      "system" -> "◇"
      "chatgpt nodes" -> "◌"
      "workflows" -> "⌘"
      "workflow inventory" -> "⌘"
      "agents" -> "●"
      "ai runtimes" -> "✦"
      "ai / models" -> "✦"
      "security" -> "◇"
      "audit" -> "▧"
      "runtime" -> "◉"
      "connectors" -> "◎"
      "pending approvals" -> "✓"
      "backup" -> "▱"
      "career" -> "◈"
      "evidence" -> "▤"
      "knowledge" -> "▥"
      _ -> "◆"
    end
  end

  defp state_class("READY"), do: "is-ready"
  defp state_class("READ_ONLY"), do: "is-read-only"
  defp state_class("PARTIAL"), do: "is-partial"
  defp state_class("DEGRADED"), do: "is-degraded"
  defp state_class("CONFIGURATION_REQUIRED"), do: "is-config-required"
  defp state_class("APPROVAL_REQUIRED"), do: "is-approval-required"
  defp state_class("DISABLED_BY_CONFIGURATION"), do: "is-disabled"
  defp state_class("REGISTRY_ONLY"), do: "is-registry-only"
  defp state_class("OPTIONAL_UNAVAILABLE"), do: "is-optional-unavailable"
  defp state_class("UNAVAILABLE"), do: "is-unavailable"
  defp state_class(_), do: ""

  defp action_class("READ"), do: "is-read"
  defp action_class("SAFE_ACTION"), do: "is-safe"
  defp action_class("AUTH_REQUIRED"), do: "is-auth-required"
  defp action_class("APPROVAL_REQUIRED"), do: "is-approval-required"
  defp action_class("BLOCKED"), do: "is-blocked"
  defp action_class("NOT_IMPLEMENTED"), do: "not-implemented"
  defp action_class(_), do: ""

  defp active?(active, "/"), do: active == "/"
  defp active?(active, path), do: active == path or String.starts_with?(active, path <> "/")
end
