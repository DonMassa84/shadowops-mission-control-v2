(() => {
  "use strict";

  const SLIDE_INTERVAL_MS = 12000;
  const DATA_REFRESH_MS = 60000;
  const BURN_IN_INTERVAL_MS = 240000;
  const STRATEGY_PER_SYSTEM = 5;
  const BURN_IN_OFFSETS = [[0, 0], [3, -2], [-2, 3], [2, 2], [-3, -1]];

  const root = document.getElementById("i7-learning-display");
  const rotation = window.ShadowOpsI7Rotation;
  if (!root || !rotation) return;

  const parseData = (name, fallback) => {
    try { return JSON.parse(root.dataset[name] || ""); } catch (_error) { return fallback; }
  };

  let systemSlides = Array.from(root.querySelectorAll("[data-slide]"));
  let strategySlides = parseData("strategySlides", []);
  let categoryWeights = parseData("categoryWeights", rotation.BASE_CATEGORY_WEIGHTS);
  let allowedContexts = parseData("allowedContexts", ["general"]);
  let activeContext = root.dataset.activeContext || "general";
  let contextOverridden = false;
  let systemIndex = -1;
  let actionIndex = 0;
  let strategySinceSystem = 0;
  let currentStrategyId = null;
  let history = [];
  let historyCursor = -1;
  let recent = new Map();
  let paused = false;
  let available = root.dataset.available === "AVAILABLE";
  let rotationTimer;
  let strategyTransitionTimer;
  let burnIndex = 0;

  const read = (plan, path, fallback = "") =>
    path.split(".").reduce((value, key) => value && value[key], plan) ?? fallback;

  const setText = (selector, value) => {
    const element = root.querySelector(selector);
    if (element) element.textContent = value ?? "";
  };

  const setBoundValues = (plan) => {
    root.querySelectorAll("[data-bind]").forEach((element) => {
      element.textContent = read(plan, element.dataset.bind, "");
    });
  };

  const replaceList = (id, values, className = "") => {
    const target = document.getElementById(id);
    if (!target) return;
    target.replaceChildren();
    (Array.isArray(values) ? values : []).forEach((value, index) => {
      const item = document.createElement("li");
      item.textContent = String(value);
      if (className && index === actionIndex) item.className = className;
      target.appendChild(item);
    });
  };

  const replaceKpis = (values) => {
    const target = document.getElementById("i7-kpis");
    if (!target) return;
    target.replaceChildren();
    (Array.isArray(values) ? values : []).forEach((kpi) => {
      const card = document.createElement("article");
      const name = document.createElement("span");
      const targetValue = document.createElement("strong");
      name.textContent = kpi.name ?? "";
      targetValue.textContent = kpi.target ?? "";
      card.append(name, targetValue);
      target.appendChild(card);
    });
  };

  const setTicker = (plan) => {
    const parts = {
      goal: read(plan, "goal.title"),
      task: read(plan, "current.title"),
      next: (plan.next || [])[actionIndex] || (plan.next || [])[0] || "",
      done: `DONE WHEN: ${read(plan, "current.done_when")}`,
      focus: `${read(plan, "execution.focus_minutes")} MIN FOCUS`,
      evidence: read(plan, "execution.output_rule")
    };
    Object.entries(parts).forEach(([key, value]) => setText(`[data-ticker="${key}"]`, value));
  };

  const applyColors = (colors) => {
    Object.entries(colors || {}).forEach(([key, value]) => {
      if (/^#[0-9a-f]{6}$/i.test(value)) root.style.setProperty(`--${key}`, value);
    });
  };

  const setMode = (mode) => {
    document.getElementById("i7-strategy-stage")?.classList.toggle("is-pool-hidden", mode !== "strategy");
    document.getElementById("i7-system-stage")?.classList.toggle("is-pool-hidden", mode !== "system");
    document.getElementById("i7-system-progress")?.classList.toggle("is-hidden", mode !== "system");
  };

  const showSystem = (index) => {
    if (systemSlides.length === 0) return;
    setMode("system");
    systemIndex = (index + systemSlides.length) % systemSlides.length;
    systemSlides.forEach((slide, current) => slide.classList.toggle("is-active", current === systemIndex));
    root.querySelectorAll(".slide-progress i").forEach((dot, current) => dot.classList.toggle("is-active", current === systemIndex));
    if (systemSlides[systemIndex]?.dataset.slide === "actions") {
      const actions = Array.from(root.querySelectorAll("#i7-next-actions li"));
      if (actions.length) {
        actionIndex = (actionIndex + 1) % actions.length;
        actions.forEach((item, current) => item.classList.toggle("is-current", current === actionIndex));
      }
    }
  };

  const showStrategy = (slide) => {
    if (!slide) return;
    setMode("strategy");
    const panel = root.querySelector("[data-strategy-slide]");
    const previousId = currentStrategyId;
    currentStrategyId = slide.id;

    const applyContent = () => {
      if (panel) panel.dataset.category = slide.category;
      setText("[data-strategy-category]", slide.category);
      setText("[data-strategy-title]", slide.title);
      const position = strategySlides.findIndex((item) => item.id === slide.id) + 1;
      setText("[data-strategy-counter]", `STRATEGY ${position} / ${strategySlides.length}`);
      const message = root.querySelector("[data-strategy-message]");
      if (message) {
        message.replaceChildren();
        String(slide.message || "").split(/\r?\n/).filter(Boolean).slice(0, 2).forEach((line) => {
          const paragraph = document.createElement("p");
          paragraph.textContent = line;
          message.appendChild(paragraph);
        });
      }
    };

    window.clearTimeout(strategyTransitionTimer);
    if (panel && previousId && previousId !== slide.id) {
      panel.classList.add("is-changing");
      strategyTransitionTimer = window.setTimeout(() => {
        applyContent();
        panel.classList.remove("is-changing");
      }, 400);
    } else {
      applyContent();
    }
  };

  const displayEntry = (entry) => {
    if (entry?.type === "strategy") {
      const slide = strategySlides.find((item) => item.id === entry.id);
      if (slide) showStrategy(slide);
    } else if (entry?.type === "system") {
      showSystem(entry.index);
    }
  };

  const recordEntry = (entry) => {
    history = history.slice(0, historyCursor + 1);
    history.push(entry);
    historyCursor = history.length - 1;
    if (history.length > 200) {
      history.shift();
      historyCursor -= 1;
    }
    displayEntry(entry);
  };

  const nextStrategy = () => {
    const now = new Date();
    const slide = rotation.selectNext(strategySlides, {
      categoryWeights,
      context: activeContext,
      currentId: currentStrategyId,
      recent,
      date: now,
      nowMs: now.getTime()
    });
    if (!slide) return false;
    recent.set(slide.id, now.getTime());
    strategySinceSystem += 1;
    recordEntry({type: "strategy", id: slide.id});
    return true;
  };

  const nextSystem = () => {
    systemIndex = (systemIndex + 1) % Math.max(systemSlides.length, 1);
    strategySinceSystem = 0;
    recordEntry({type: "system", index: systemIndex});
  };

  const next = () => {
    if (!available) return;
    if (historyCursor < history.length - 1) {
      historyCursor += 1;
      displayEntry(history[historyCursor]);
      return;
    }
    if (strategySlides.length === 0) {
      nextSystem();
    } else if (strategySinceSystem >= STRATEGY_PER_SYSTEM) {
      nextSystem();
    } else {
      if (!nextStrategy()) nextSystem();
    }
  };

  const previous = () => {
    if (historyCursor > 0) {
      historyCursor -= 1;
      displayEntry(history[historyCursor]);
    }
  };

  const restartRotation = () => {
    window.clearInterval(rotationTimer);
    if (!paused && available) rotationTimer = window.setInterval(next, SLIDE_INTERVAL_MS);
  };

  const renderPlan = (plan) => {
    available = plan.availability === "AVAILABLE";
    root.dataset.available = plan.availability || "UNAVAILABLE";
    root.classList.toggle("is-unavailable", !available);
    setText("[data-bind=detail]", plan.detail || "Learning plan unavailable");
    if (!available) {
      window.clearInterval(rotationTimer);
      return;
    }

    applyColors(plan.colors);
    setBoundValues(plan);
    actionIndex %= Math.max((plan.next || []).length, 1);
    replaceList("i7-next-actions", plan.next, "is-current");
    replaceList("i7-writing-framework", plan.writing_framework);
    replaceKpis(plan.kpis);
    setTicker(plan);
    strategySlides = Array.isArray(plan.strategy?.slides) ? plan.strategy.slides : [];
    categoryWeights = plan.strategy?.category_weights || rotation.BASE_CATEGORY_WEIGHTS;
    allowedContexts = Array.isArray(plan.allowed_contexts) ? plan.allowed_contexts : ["general"];
    if (!contextOverridden) activeContext = plan.active_context || "general";
    recent = new Map(Array.from(recent).filter(([id]) => strategySlides.some((slide) => slide.id === id)));
    history = history.filter((entry) => entry.type === "system" || strategySlides.some((slide) => slide.id === entry.id));
    historyCursor = Math.min(historyCursor, history.length - 1);
    currentStrategyId = strategySlides.some((slide) => slide.id === currentStrategyId) ? currentStrategyId : null;

    if (history.length === 0) {
      if (!nextStrategy()) recordEntry({type: "system", index: 0});
    } else {
      displayEntry(history[Math.max(historyCursor, 0)]);
    }
    restartRotation();
  };

  const refreshPlan = async () => {
    try {
      const response = await fetch("/api/learning/plan", {headers: {accept: "application/json"}, cache: "no-store"});
      if (!response.ok) throw new Error(`learning plan HTTP ${response.status}`);
      renderPlan(await response.json());
    } catch (_error) {
      renderPlan({availability: "UNAVAILABLE", detail: "Learning plan unavailable"});
    }
  };

  document.addEventListener("keydown", (event) => {
    if (event.key === "ArrowRight") { next(); restartRotation(); }
    if (event.key === "ArrowLeft") { previous(); restartRotation(); }
    if (event.code === "Space") { event.preventDefault(); paused = !paused; restartRotation(); }
    if (event.key.toLowerCase() === "s" && available) { nextSystem(); restartRotation(); }
    if (event.key.toLowerCase() === "c" && allowedContexts.length > 0) {
      const index = allowedContexts.indexOf(activeContext);
      activeContext = allowedContexts[(index + 1) % allowedContexts.length];
      contextOverridden = true;
      if (!nextStrategy()) nextSystem();
      restartRotation();
    }
    if (event.key.toLowerCase() === "r") {
      paused = false;
      if (!nextStrategy()) nextSystem();
      restartRotation();
    }
  });

  if (!nextStrategy()) recordEntry({type: "system", index: 0});
  restartRotation();
  window.setInterval(refreshPlan, DATA_REFRESH_MS);
  window.setInterval(() => {
    burnIndex = (burnIndex + 1) % BURN_IN_OFFSETS.length;
    const [x, y] = BURN_IN_OFFSETS[burnIndex];
    root.style.setProperty("--burn-x", `${x}px`);
    root.style.setProperty("--burn-y", `${y}px`);
  }, BURN_IN_INTERVAL_MS);
})();
