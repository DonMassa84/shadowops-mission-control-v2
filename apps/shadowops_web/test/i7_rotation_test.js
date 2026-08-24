import test from "node:test";
import assert from "node:assert/strict";
import "../priv/static/assets/i7-rotation.js";

const rotation = globalThis.ShadowOpsI7Rotation;

const slide = (id, category, overrides = {}) => ({
  id,
  title: id,
  message: "test-only structural fixture",
  category,
  weight: 1,
  contexts: ["general"],
  cooldown_minutes: 0,
  priority: "P1",
  ...overrides
});

const day = new Date("2026-08-23T12:00:00Z");
const night = new Date("2026-08-23T21:00:00Z");

test("base category weighting and seeded selection are deterministic", () => {
  const slides = [
    slide("core", "CORE"),
    slide("self", "SELF_CONTROL"),
    slide("social", "SOCIAL_STRATEGY"),
    slide("career", "CAREER_IHK"),
    slide("technical", "TECHNICAL"),
    slide("review", "REVIEW")
  ];
  assert.deepEqual(
    rotation.weightedCandidates(slides, {context: "general", date: day}).map(({weight}) => weight),
    [40, 15, 10, 15, 15, 5]
  );

  const first = rotation.createSeededRng(4242);
  const second = rotation.createSeededRng(4242);
  const sequence = (rng) => Array.from({length: 12}, () => rotation.selectNext(slides, {date: day, random: rng}).id);
  assert.deepEqual(sequence(first), sequence(second));
});

test("current slide is never selected consecutively and cooldown is respected", () => {
  const slides = [
    slide("a", "CORE", {cooldown_minutes: 60}),
    slide("b", "CORE", {cooldown_minutes: 60}),
    slide("c", "CORE", {cooldown_minutes: 60})
  ];
  const nowMs = day.getTime();
  const recent = new Map([["b", nowMs - 1000]]);
  const selected = rotation.selectNext(slides, {currentId: "a", recent, nowMs, date: day, random: 0});
  assert.equal(selected.id, "c");
  assert.notEqual(selected.id, "a");
  assert.equal(rotation.selectNext([slides[0]], {currentId: "a", date: day}), null);
  assert.equal(
    rotation.selectNext(slides, {
      currentId: "a",
      recent: new Map([["b", nowMs], ["c", nowMs]]),
      nowMs,
      date: day
    }),
    null
  );
});

test("configured contexts apply only the documented category multipliers", () => {
  const slides = [
    slide("core-01", "CORE"),
    slide("self", "SELF_CONTROL"),
    slide("social", "SOCIAL_STRATEGY"),
    slide("career", "CAREER_IHK"),
    slide("technical", "TECHNICAL"),
    slide("review", "REVIEW")
  ];
  const weights = (context) => Object.fromEntries(
    rotation.weightedCandidates(slides, {context, date: day}).map(({slide: item, weight}) => [item.category, weight])
  );
  assert.equal(weights("career").CAREER_IHK, 30);
  assert.equal(weights("career").CORE, 52);
  assert.equal(weights("ihk").CAREER_IHK, 37.5);
  assert.equal(weights("technical").TECHNICAL, 37.5);
  assert.equal(weights("social").SOCIAL_STRATEGY, 20);
  assert.equal(weights("social").SELF_CONTROL, 22.5);
  assert.equal(weights("recovery").SELF_CONTROL, 30);
  assert.equal(weights("recovery").REVIEW, 10);
});

test("Berlin night weighting favors control and review without disabling work contexts", () => {
  const slides = [
    slide("core-07", "CORE"),
    slide("self", "SELF_CONTROL"),
    slide("career", "CAREER_IHK"),
    slide("technical", "TECHNICAL"),
    slide("review", "REVIEW")
  ];
  assert.equal(rotation.isNight(day), false);
  assert.equal(rotation.isNight(night), true);
  const values = Object.fromEntries(
    rotation.weightedCandidates(slides, {context: "technical", date: night}).map(({slide: item, weight}) => [item.id, weight])
  );
  assert.equal(values.self, 30);
  assert.equal(values.review, 10);
  assert.equal(values["core-07"], 86.4);
  assert.equal(values.technical, 22.5);
  assert.ok(values.career > 0);
});
