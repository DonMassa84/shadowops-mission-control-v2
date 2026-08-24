defmodule ShadowOpsWeb.I7DisplayLive do
  use Phoenix.LiveView

  alias ShadowOpsCore.LearningFocus

  @impl true
  def mount(_params, _session, socket) do
    {:ok, plan} = LearningFocus.load()
    {:ok, assign(socket, plan: plan)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main
      id="i7-learning-display"
      class={if @plan["availability"] == "AVAILABLE", do: "i7-display", else: "i7-display is-unavailable"}
      data-available={@plan["availability"]}
      data-active-context={@plan["active_context"] || "general"}
      data-allowed-contexts={Jason.encode!(@plan["allowed_contexts"] || ["general"])}
      data-strategy-slides={Jason.encode!(strategy_slides(@plan))}
      data-category-weights={Jason.encode!(get_in(@plan, ["strategy", "category_weights"]) || %{})}
      phx-update="ignore"
      style={color_variables(@plan["colors"])}
    >
      <div id="i7-unavailable" class="i7-unavailable" role="status">
        <h1>UNAVAILABLE</h1>
        <p data-bind="detail">{@plan["detail"]}</p>
      </div>

      <div
        id="i7-strategy-stage"
        class={if strategy_available?(@plan), do: "i7-stage strategy-stage", else: "i7-stage strategy-stage is-pool-hidden"}
      >
        <% first = List.first(strategy_slides(@plan)) || %{} %>
        <section class="i7-slide strategy-slide is-active" data-strategy-slide data-category={first["category"] || "CORE"}>
          <div class="strategy-meta">
            <p class="eyebrow" data-strategy-category>{first["category"]}</p>
            <p data-strategy-counter>STRATEGY 1 / {length(strategy_slides(@plan))}</p>
          </div>
          <h1 data-strategy-title>{first["title"]}</h1>
          <div class="strategy-message" data-strategy-message>
            <p :for={line <- message_lines(first["message"])}>{line}</p>
          </div>
        </section>
      </div>

      <div
        class={if strategy_available?(@plan), do: "i7-stage system-stage is-pool-hidden", else: "i7-stage system-stage"}
        id="i7-system-stage"
      >
        <section class="i7-slide gradient-mission is-active" data-slide="mission">
          <p class="eyebrow">MISSION</p>
          <h1 data-bind="goal.title">{value(@plan, ["goal", "title"])}</h1>
          <p class="lead" data-bind="goal.smart">{value(@plan, ["goal", "smart"])}</p>
        </section>

        <section class="i7-slide gradient-now" data-slide="now">
          <p class="eyebrow action">JETZT</p>
          <h1 data-bind="current.title">{value(@plan, ["current", "title"])}</h1>
          <p class="lead" data-bind="current.instruction">{value(@plan, ["current", "instruction"])}</p>
          <div class="done-when"><span>DONE WHEN</span><strong data-bind="current.done_when">{value(@plan, ["current", "done_when"])}</strong></div>
        </section>

        <section class="i7-slide gradient-actions" data-slide="actions">
          <p class="eyebrow action">NEXT ACTIONS</p>
          <h1>Nächster belastbarer Schritt</h1>
          <ol id="i7-next-actions" class="action-list">
            <li :for={{item, index} <- Enum.with_index(list(@plan, "next"))} class={if index == 0, do: "is-current"}>{item}</li>
          </ol>
        </section>

        <section class="i7-slide gradient-review" data-slide="algorithm">
          <p class="eyebrow review">PERSONAL STRATEGY RULES</p>
          <h1>1–10: Auswahl, Haltung, Substanz</h1>
          <ol id="i7-writing-framework" class="algorithm-grid">
            <li :for={item <- list(@plan, "writing_framework")}>{item}</li>
          </ol>
        </section>

        <section class="i7-slide gradient-evidence" data-slide="kpis">
          <p class="eyebrow success">KPIs / EVIDENCE</p>
          <h1>Autonomie statt Manipulation</h1>
          <div id="i7-kpis" class="kpi-grid">
            <article :for={kpi <- list(@plan, "kpis")}><span>{kpi["name"]}</span><strong>{kpi["target"]}</strong></article>
          </div>
        </section>

        <section class="i7-slide gradient-focus" data-slide="focus">
          <p class="eyebrow focus">FOCUS BLOCK</p>
          <h1><span data-bind="execution.focus_minutes">{value(@plan, ["execution", "focus_minutes"])}</span>/<span data-bind="execution.break_minutes">{value(@plan, ["execution", "break_minutes"])}</span> Minuten</h1>
          <div class="rules">
            <p><span>FOCUS</span><strong data-bind="execution.rule">{value(@plan, ["execution", "rule"])}</strong></p>
            <p><span>ERROR</span><strong data-bind="execution.error_rule">{value(@plan, ["execution", "error_rule"])}</strong></p>
            <p><span>OUTPUT</span><strong data-bind="execution.output_rule">{value(@plan, ["execution", "output_rule"])}</strong></p>
          </div>
        </section>
      </div>

      <div class="ticker-viewport" aria-label="Learning focus ticker">
        <div id="i7-ticker" class="ticker-track">
          <span data-ticker="goal">{value(@plan, ["goal", "title"])}</span><b>◆</b>
          <span data-ticker="task">{value(@plan, ["current", "title"])}</span><b>◆</b>
          <span data-ticker="next">{List.first(list(@plan, "next"))}</span><b>◆</b>
          <span data-ticker="done">DONE WHEN: {value(@plan, ["current", "done_when"])}</span><b>◆</b>
          <span data-ticker="focus">{value(@plan, ["execution", "focus_minutes"])} MIN FOCUS</span><b>◆</b>
          <span data-ticker="evidence">{value(@plan, ["execution", "output_rule"])}</span>
        </div>
      </div>

      <div id="i7-system-progress" class={if strategy_available?(@plan), do: "slide-progress is-hidden", else: "slide-progress"} aria-hidden="true"><i :for={index <- 0..5} class={if index == 0, do: "is-active"}></i></div>
      <script src="/assets/i7-rotation.js" defer></script>
      <script src="/assets/i7-display.js" defer></script>
    </main>

    <style>
      :root { color-scheme: dark; }
      html, body { margin: 0; overflow: hidden; background: #071019; }
      .i7-display { --burn-x: 0px; --burn-y: 0px; min-height: 100vh; overflow: hidden; position: relative; background: var(--background); color: var(--text); font-family: Inter, ui-sans-serif, system-ui, sans-serif; }
      .i7-stage { position: absolute; inset: 0 0 5rem; opacity: 1; visibility: visible; transform: translate(var(--burn-x), var(--burn-y)); transition: transform 8s ease-in-out, opacity 800ms ease, visibility 0s linear 0s; }
      .i7-stage.is-pool-hidden { opacity: 0; visibility: hidden; pointer-events: none; transition: transform 8s ease-in-out, opacity 800ms ease, visibility 0s linear 800ms; }
      .is-hidden { display: none !important; }
      .i7-slide { position: absolute; inset: 0; box-sizing: border-box; padding: clamp(3rem, 7vw, 8rem); display: flex; flex-direction: column; justify-content: center; opacity: 0; visibility: hidden; transition: opacity 800ms ease, visibility 0s linear 800ms; }
      .i7-slide.is-active { opacity: 1; visibility: visible; transition: opacity 800ms ease; }
      .gradient-mission { background: radial-gradient(circle at 80% 20%, color-mix(in srgb, var(--focus) 18%, transparent), transparent 42%), linear-gradient(145deg, var(--background), var(--panel)); }
      .gradient-now { background: radial-gradient(circle at 18% 78%, color-mix(in srgb, var(--action) 17%, transparent), transparent 38%), linear-gradient(120deg, var(--background), var(--panel)); }
      .gradient-actions { background: linear-gradient(150deg, color-mix(in srgb, var(--action) 11%, var(--background)), var(--background) 55%, var(--panel)); }
      .gradient-review { background: radial-gradient(circle at 75% 70%, color-mix(in srgb, var(--review) 17%, transparent), transparent 40%), linear-gradient(135deg, var(--background), var(--panel)); }
      .gradient-evidence { background: radial-gradient(circle at 20% 25%, color-mix(in srgb, var(--success) 15%, transparent), transparent 38%), linear-gradient(155deg, var(--background), var(--panel)); }
      .gradient-focus { background: linear-gradient(125deg, color-mix(in srgb, var(--focus) 10%, var(--background)), var(--background), color-mix(in srgb, var(--review) 8%, var(--panel))); }
      .strategy-slide { background: radial-gradient(circle at 82% 18%, color-mix(in srgb, var(--category-color, var(--focus)) 15%, transparent), transparent 42%), linear-gradient(145deg, var(--background), var(--panel)); }
      .strategy-slide.is-changing { opacity: 0; }
      .strategy-slide[data-category="SELF_CONTROL"] { --category-color: var(--recovery); }
      .strategy-slide[data-category="SOCIAL_STRATEGY"] { --category-color: var(--review); }
      .strategy-slide[data-category="CAREER_IHK"] { --category-color: var(--success); }
      .strategy-slide[data-category="TECHNICAL"] { --category-color: var(--focus); }
      .strategy-slide[data-category="REVIEW"] { --category-color: var(--action); }
      .strategy-meta { display: flex; justify-content: space-between; align-items: center; max-width: 80rem; color: var(--muted); font-weight: 750; letter-spacing: .1em; }
      .strategy-meta .eyebrow { color: var(--category-color, var(--focus)); }
      .strategy-message { max-width: 72rem; color: var(--muted); font-size: clamp(1.4rem, 2.3vw, 2.5rem); line-height: 1.35; }
      .strategy-message p { margin: .35em 0; }
      h1 { margin: .2em 0; max-width: 18ch; font-size: clamp(3rem, 6.5vw, 7rem); line-height: .98; letter-spacing: -.04em; }
      .lead { max-width: 58ch; color: var(--muted); font-size: clamp(1.35rem, 2.2vw, 2.4rem); line-height: 1.38; }
      .eyebrow { color: var(--focus); font-size: clamp(1rem, 1.4vw, 1.5rem); font-weight: 800; letter-spacing: .18em; }
      .eyebrow.action, .action-list .is-current { color: var(--action); }
      .eyebrow.success { color: var(--success); } .eyebrow.review { color: var(--review); }
      .done-when { margin-top: 2rem; max-width: 70rem; padding: 1.4rem 1.8rem; border-left: .35rem solid var(--success); background: color-mix(in srgb, var(--success) 8%, var(--panel)); }
      .done-when span, .rules span, .kpi-grid span { display: block; color: var(--success); font-size: .9rem; font-weight: 800; letter-spacing: .12em; }
      .done-when strong { display: block; margin-top: .35rem; font-size: clamp(1.25rem, 2vw, 2rem); }
      .action-list { display: grid; gap: 1rem; max-width: 72rem; font-size: clamp(1.25rem, 2vw, 2.2rem); color: var(--muted); }
      .action-list li { padding: .75rem 1rem; transition: color 800ms ease, transform 800ms ease; }
      .action-list li.is-current { transform: translateX(1rem); font-weight: 750; }
      .algorithm-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .7rem 2rem; max-width: 80rem; font-size: clamp(1rem, 1.6vw, 1.7rem); }
      .algorithm-grid li::marker { color: var(--review); font-weight: 800; }
      .kpi-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 1rem; max-width: 75rem; }
      .kpi-grid article { padding: 1.3rem; border: 1px solid color-mix(in srgb, var(--success) 35%, var(--panel)); background: color-mix(in srgb, var(--success) 7%, var(--panel)); }
      .kpi-grid strong { display: block; margin-top: .5rem; font-size: clamp(1.2rem, 2vw, 2rem); }
      .rules { display: grid; gap: 1rem; max-width: 75rem; } .rules p { margin: 0; padding: 1rem 1.3rem; background: color-mix(in srgb, var(--panel) 90%, transparent); }
      .rules p:nth-child(2) span { color: var(--error); } .rules p:nth-child(3) span { color: var(--success); }
      .rules strong { display: block; margin-top: .35rem; font-size: clamp(1.05rem, 1.55vw, 1.55rem); }
      .ticker-viewport { position: absolute; left: 0; right: 0; bottom: 0; height: 4rem; overflow: hidden; display: flex; align-items: center; border-top: 1px solid color-mix(in srgb, var(--focus) 30%, var(--panel)); background: color-mix(in srgb, var(--panel) 94%, black); }
      .ticker-track { display: flex; width: max-content; white-space: nowrap; gap: 2rem; font-size: 1.25rem; animation: ticker 55s linear infinite; will-change: transform; }
      .ticker-track b { color: var(--action); } @keyframes ticker { from { transform: translateX(100vw); } to { transform: translateX(-100%); } }
      .slide-progress { position: absolute; right: 2rem; bottom: 5.5rem; display: flex; gap: .5rem; } .slide-progress i { width: .6rem; height: .6rem; border-radius: 50%; background: var(--muted); opacity: .35; transition: opacity 800ms ease, background 800ms ease; } .slide-progress i.is-active { opacity: 1; background: var(--focus); }
      .i7-unavailable { display: none; min-height: 100vh; place-content: center; text-align: center; background: var(--background); color: var(--error); } .is-unavailable .i7-unavailable { display: grid; } .is-unavailable .i7-stage, .is-unavailable .ticker-viewport, .is-unavailable .slide-progress { display: none; }
      @media (prefers-reduced-motion: reduce) { .i7-slide { transition-duration: 0ms; } .ticker-track { animation-duration: 100s; } }
    </style>
    """
  end

  defp value(plan, path), do: get_in(plan, path) || ""
  defp list(plan, key), do: if(is_list(plan[key]), do: plan[key], else: [])
  defp strategy_slides(plan), do: get_in(plan, ["strategy", "slides"]) || []
  defp strategy_available?(plan), do: strategy_slides(plan) != []
  defp message_lines(message) when is_binary(message), do: String.split(message, "\n", trim: true)
  defp message_lines(_), do: []

  defp color_variables(colors) do
    Enum.map_join(colors, ";", fn {key, value} -> "--#{key}:#{value}" end)
  end
end
