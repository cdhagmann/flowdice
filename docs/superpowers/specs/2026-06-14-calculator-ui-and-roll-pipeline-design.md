# Increment #4 — Calculator UI + Roll Pipeline Design

- **Date:** 2026-06-14
- **Status:** Approved (visual direction signed off; architecture below)
- **Parent design:** `docs/superpowers/specs/2026-06-13-flowdice-architecture-and-roadmap-design.md`
- **Builds on:** #1 engine · #2 Rails + `/parse` · #3 Opal-compiled `FlowDice.evaluate`. On `main` at `b8cc3da`.

## Goal

Make FlowDice rollable from the browser: a mobile-first calculator that builds
notation by tapping, rolls **client-side** via the Opal evaluator, and shows the
result — the first visible, usable UI.

## Scope

**In:** serve the compiled Opal evaluator to the browser (importmap); the roll
pipeline (IndexedDB plan-cache + `POST /parse` on miss + `crypto`-backed RNG +
`FlowDice.evaluate`); the Stimulus calculator controller (the approved lean input
model); the `/` Dice view (hand-written HTML/CSS per the approved design); the
result bottom-sheet; Capybara system specs.

**Out (later):** live-as-you-type explanation (#8) — in #4 the explanation appears
on the result sheet; Favorites/History views (#6) — tabs are present but inert;
service-worker app-shell caching so the app *loads* offline (#7); enabling CSP
(pre-production). Text-input mode is #5.

## Decisions

| # | Decision | Notes |
|---|----------|-------|
| 1 | **Committed, rake-built Opal artifact, importmap-pinned** | `rake opal:build` → `vendor/javascript/flow_dice.js`; pinned `flow_dice`; a CI check fails if it's stale vs the engine. |
| 2 | **Parse-on-roll, cache by notation** | ROLL parses (if uncached) via `/parse`, caches `{plan, explanation}` in IndexedDB keyed by notation, then evaluates client-side. Re-rolls of a cached notation need no network (offline-capable). |
| 3 | **`crypto.getRandomValues` RNG with rejection sampling** | Unbiased (matches Ruby `SecureRandom`); no modulo bias. |
| 4 | **Plain CSS, hand-written per the approved design** | No Tailwind (the #2 choice); frontend-design skill drives the build. |
| 5 | **System specs via Capybara + headless Chrome** | Tests the whole wiring in a real browser; exact-value correctness is already covered by #3 parity, so system specs assert structure/range. |

## Section A — Visual design (approved)

Dark theme, electric-violet accent (`#8b5cff`); surfaces `#13141b` on bg `#0b0c10`;
warm→cool color-coded dice (d4 `#ff5d5d` → d20 `#38bdf8`, d% `#f472d0`, dN slate);
`ui-monospace` tabular for all dice/number text; 12–18px radii.

**Lean input model:** tap a die to add/increment its count (`d20`→`2d20`);
`kh/kl/c/C` toggle on the active term (active = violet fill); a compact `+/−`
stepper for the flat modifier; a `123` toggle reveals a full number pad for rare
multi-digit entry; `×` clears.

**Layout (`/`):** brand + slogan → Dice/Favorites/History tabs (only Dice wired) →
monospace notation readout + clear → 3×3 dice grid → `kh/kl/c/C` strip → modifier
stepper → ROLL (+ dimmed ♥, which is #6). (The readout has room for an explanation
line, but in #4 the explanation is shown on the **result sheet** — live-as-you-type
in the readout is #8.)

**Result = bottom sheet:** notation, huge tabular **total**, individual dice as
uniform flex-centered pills in their die color (kept = ringed, **dropped =
struck-through + dimmed**), plain-English breakdown, `Roll again / ♥ / ×`. For
`d%`, show the tens/units components (the evaluator already emits `d%(tens)` /
`d%(units)` dice records, with the 00→100 case folded into the total).

## Section B — Serving the Opal evaluator

- `rake opal:build`: runs `Opal::Builder` (`build("opal")` + `build("flow_dice/opal/entry")`,
  with `packs/dice_engine/lib` on the Opal path — the exact sequence proven in #3)
  and writes the JS to `vendor/javascript/flow_dice.js`.
- Pin it in `config/importmap.rb`: `pin "flow_dice", to: "flow_dice.js"`. Importing
  it executes the bundle, which defines `globalThis.FlowDice.evaluate` (per #3).
- **Commit the built artifact.** A spec/CI check rebuilds it and fails if it differs
  from the committed file (`git diff --exit-code`) — so the artifact can't drift
  from the engine. Document `rake opal:build` as the regen step.

## Section C — Roll pipeline (`app/javascript/flow_dice/roll_pipeline.js`)

A small ES module, no dependencies (browser APIs only):

- `rollNotation(notation) -> Promise<{result, explanation}>`:
  1. Look up `notation` in the **IndexedDB** `plans` store.
  2. On miss: `POST /parse` (`Content-Type: application/json`, body `{notation}`),
     receive `{notation, plan, explanation}`, store `{plan, explanation}` keyed by
     notation. On a `422`, reject with the server's error message (the UI surfaces it).
  3. Call `FlowDice.evaluate(JSON.stringify(plan), notation, secureRng)`, `JSON.parse`
     the returned string, and resolve `{result, explanation}`.
- `secureRng = { int: (min, max) => secureInt(min, max) }` where `secureInt` uses
  **rejection sampling** over `crypto.getRandomValues(new Uint32Array(1))` to draw an
  unbiased integer in the inclusive range. (Matches the `{int(min,max)}` contract #3 expects.)
- A minimal promise-wrapped IndexedDB helper (`open`, `get`, `put`) — hand-written,
  ~30 lines; no library.
- Re-rolls reuse the cached plan → no network → works offline (once cached).

## Section D — Stimulus calculator controller (`calculator_controller.js`)

- Maintains the **notation string** as the source of truth, built from button taps,
  and renders the readout. Targets: `notation` (readout), `explanation`, dice
  buttons, `kh/kl/c/C`, stepper value, `roll`, the result sheet.
- Actions: `addDie(dX)` (append/increment the current die term), `toggleKeep(kh|kl)`,
  `toggleCrit(c|C)`, `stepModifier(±1)`, `togglePad`, `pad(digit/op)`, `clear`.
- `roll()`: call `rollNotation(currentNotation)` → on success, render the result
  sheet (Section F) and the explanation; on `422`, flash the error in the readout
  area. Disable ROLL when the notation is empty/invalid.
- Notation building is plain string assembly mirroring the engine's grammar (e.g.
  active term = the last dice group; `kh` appends/removes `kh` on it). Kept simple;
  the server parser is the validator (a bad build → 422 → surfaced).

## Section E — Views & routes

- `/` (Dice) is built: `home#index` becomes the calculator (replacing the
  placeholder), markup driven by `calculator_controller`.
- The **Favorites/History tabs are present but inert** in #4 (no link target yet);
  their routes/views arrive in #6. (Keeps the approved layout; URL-per-view nav is
  added with the real views, preserving Hotwire-Native readiness.)

## Section F — Result rendering

The result sheet is rendered client-side from the `FlowDice.evaluate` result
(`{kind, total, notation, dice:[{die,value,kept}], breakdown}`):
- `total` huge + tabular; `notation` small above it.
- Each `dice[]` entry → a pill: color from the die label/kind, struck-through +
  dimmed when `kept === false`, ringed when kept. `d%(tens)`/`d%(units)` render as
  their own pills.
- `breakdown` as the muted line.
- `Roll again` re-runs `rollNotation` (cached plan → instant); `♥` is inert (#6);
  `×` dismisses.

## Section G — Testing

- **System specs (Capybara + headless Chrome, e.g. cuprite/ferrum — no Selenium server):**
  load `/`, tap `d20` twice → readout shows `2d20`; tap `kh` → `2d20kh`; ROLL →
  result sheet appears with a `total` in the valid range and the right number of
  dice pills. Assert **structure/range**, not exact values (exact JS/Ruby agreement
  is already proven by #3's parity specs). A `d%` roll shows tens/units pills.
- The `/parse` request spec already exists (#2).
- The Opal-artifact freshness check (Section B) runs in the suite.
- Full `bundle exec rspec` stays green.

## Section H — Offline (partial, by design)

The IndexedDB plan-cache + client-side evaluation means **re-rolling a
previously-parsed notation works with no network**. Making the app *load* offline
(service worker caching the app shell + `flow_dice.js`) is **#7**.

## Risks

- **Headless browser availability.** System specs need headless Chrome + a driver
  (cuprite/ferrum). If unavailable in the environment, that's a blocker to surface
  (as mini_racer was in #3) — fall back to a documented manual-verification note only
  with explicit say-so.
- **Notation-building complexity.** Client-side string assembly for edge cases (e.g.
  toggling `kh` off, custom faces) can get fiddly; keep it minimal and lean on the
  server parser as validator (422 → surfaced), rather than reimplementing grammar.
- **Artifact drift.** Mitigated by the freshness check (Section B).
