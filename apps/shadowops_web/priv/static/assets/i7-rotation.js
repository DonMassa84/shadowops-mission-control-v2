(function (root, factory) {
  "use strict";
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  root.ShadowOpsI7Rotation = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  const BASE_CATEGORY_WEIGHTS = {
    CORE: 40,
    SELF_CONTROL: 15,
    SOCIAL_STRATEGY: 10,
    CAREER_IHK: 15,
    TECHNICAL: 15,
    REVIEW: 5
  };
  const RECOVERY_CORE_IDS = new Set(["core-07", "core-08", "core-11", "core-12"]);

  const contextMultiplier = (slide, context) => {
    switch (context) {
      case "career":
        if (slide.category === "CAREER_IHK") return 2;
        if (slide.category === "CORE") return 1.3;
        break;
      case "ihk":
        if (slide.category === "CAREER_IHK") return 2.5;
        if (slide.category === "TECHNICAL" || slide.category === "CORE") return 1.3;
        break;
      case "technical":
        if (slide.category === "TECHNICAL") return 2.5;
        if (slide.category === "CORE") return 1.2;
        break;
      case "social":
        if (slide.category === "SOCIAL_STRATEGY") return 2;
        if (slide.category === "SELF_CONTROL") return 1.5;
        if (slide.category === "CORE") return 1.3;
        break;
      case "recovery":
        if (slide.category === "SELF_CONTROL" || slide.category === "REVIEW") return 2;
        if (RECOVERY_CORE_IDS.has(slide.id)) return 1.5;
        break;
    }
    return 1;
  };

  const berlinMinutes = (date) => {
    const parts = new Intl.DateTimeFormat("en-GB", {
      timeZone: "Europe/Berlin",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23"
    }).formatToParts(date);
    const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
    return Number(values.hour) * 60 + Number(values.minute);
  };

  const isNight = (date) => berlinMinutes(date) >= 22 * 60 + 30;

  const createSeededRng = (seed) => {
    let state = Number(seed) >>> 0;
    return () => {
      state = (1664525 * state + 1013904223) >>> 0;
      return state / 4294967296;
    };
  };

  const nightMultiplier = (slide, date) => {
    if (!isNight(date)) return 1;
    if (slide.category === "SELF_CONTROL" || slide.category === "REVIEW") return 2;
    if (RECOVERY_CORE_IDS.has(slide.id)) return 1.8;
    if (slide.category === "CAREER_IHK") return 0.7;
    if (slide.category === "TECHNICAL") return 0.6;
    return 1;
  };

  const lastShown = (recent, id) => {
    if (recent instanceof Map) return recent.get(id);
    return recent ? recent[id] : undefined;
  };

  const eligibleSlides = (slides, currentId, recent, nowMs) => {
    const withoutCurrent = slides.filter((slide) => slide.id !== currentId);
    return withoutCurrent.filter((slide) => {
      const shownAt = lastShown(recent, slide.id);
      return shownAt === undefined || nowMs - shownAt >= slide.cooldown_minutes * 60000;
    });
  };

  const weightedCandidates = (slides, options = {}) => {
    const context = options.context || "general";
    const date = options.date || new Date();
    const nowMs = options.nowMs ?? date.getTime();
    const candidates = eligibleSlides(slides, options.currentId, options.recent, nowMs);
    const categoryCounts = candidates.reduce((counts, slide) => {
      counts[slide.category] = (counts[slide.category] || 0) + 1;
      return counts;
    }, {});

    return candidates.map((slide) => ({
      slide,
      weight:
        ((options.categoryWeights || BASE_CATEGORY_WEIGHTS)[slide.category] || 0) /
        categoryCounts[slide.category] *
        slide.weight *
        contextMultiplier(slide, context) *
        nightMultiplier(slide, date)
    }));
  };

  const selectNext = (slides, options = {}) => {
    if (!Array.isArray(slides) || slides.length === 0) return null;
    const candidates = weightedCandidates(slides, options).filter((entry) => entry.weight > 0);
    if (candidates.length === 0) return null;

    const total = candidates.reduce((sum, entry) => sum + entry.weight, 0);
    const randomValue = typeof options.random === "function" ? options.random() : (options.random ?? Math.random());
    const random = Math.min(Math.max(randomValue, 0), 0.999999999999);
    let threshold = random * total;

    for (const entry of candidates) {
      threshold -= entry.weight;
      if (threshold < 0) return entry.slide;
    }
    return candidates[candidates.length - 1].slide;
  };

  return {
    BASE_CATEGORY_WEIGHTS,
    RECOVERY_CORE_IDS,
    berlinMinutes,
    contextMultiplier,
    createSeededRng,
    eligibleSlides,
    isNight,
    nightMultiplier,
    selectNext,
    weightedCandidates
  };
});
