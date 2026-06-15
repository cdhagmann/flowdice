# Increment #2 — Rails Skeleton + Packwerk + `/parse` Design

- **Date:** 2026-06-14
- **Status:** Approved (design)
- **Parent design:** `docs/superpowers/specs/2026-06-13-flowdice-architecture-and-roadmap-design.md`
- **Builds on:** Increment #1 — the `FlowDice::Engine` dice engine (`packs/dice_engine/`, merged at `bc81ecf`).

## Goal

Wrap a Rails 8 app around the existing dice engine, wire the engine in as a
Packwerk-enforced pack, and expose the stateless `POST /parse` endpoint — the
canonical contract every later client (web, MCP, Discord, native) consumes.

## Decisions

| # | Decision | Notes |
|---|----------|-------|
| 1 | **Vanilla Rails 8 defaults**, `rails new . --skip-test` | Keep SQLite + Active Record + the Solid stack (present but unused by app code in Phase 1; ready for Phase 3). RSpec instead of Minitest. |
| 2 | **Importmap** for JS | Rails 8 default, no Node toolchain. The Opal evaluator (increment #3) ships as a vendored/pinned JS file. |
| 3 | **Plain CSS / Propshaft** | No CSS framework; custom styles for the calculator come in #4. |
| 4 | **Packwerk now** | The engine is restructured to be Zeitwerk-autoloadable and enforced as a pack with `FlowDice::Engine` as its sole public constant. |
| 5 | Rails app module is `Flowdice`; engine module stays `FlowDice` | Distinct constants — no clash. |

## Section A — Scaffold

- `rails new . --skip-test` inside the existing repo. It generates around `docs/`
  and `packs/`. Keeps the full Rails 8 default stack (SQLite/AR/Solid, importmap,
  Propshaft, Hotwire turbo+stimulus, PWA stubs, Kamal/Dockerfile/CI).
- Add `.ruby-version` consistent with the engine (Ruby 3.3+).
- Resolve any `rails new` file conflicts at the repo root (none expected — no
  root `Gemfile`/`README` exists yet).

## Section B — Engine → Rails via Packwerk

**The engine specs must stay green at every step — they are the regression safety
net for the restructuring.** (Count drops 82 → 81 once `version_spec.rb` is removed
per B1; the rest must keep passing.)

**B1. Zeitwerk-conformance restructuring** of `packs/dice_engine/lib/flow_dice/`
(one constant per file, file name ↔ constant name):

| Current | New | Constant |
|---------|-----|----------|
| `rng.rb` | `secure_random_rng.rb` | `FlowDice::SecureRandomRng` |
| `errors.rb` | `parse_error.rb` | `FlowDice::ParseError` |
| `value_objects.rb` | `parse_result.rb` + `result.rb` | `FlowDice::ParseResult`, `FlowDice::Result` |
| `version.rb` (+ spec) | *deleted* | unused scaffolding (not a gem) |
| `flow_dice.rb` | *require chain removed* | implicit `FlowDice` namespace from the dir |

`parser.rb`, `evaluator.rb`, `explanation.rb`, `plan.rb`, `engine.rb` already
match Zeitwerk naming and stay. Internal `require_relative`s are removed (Zeitwerk
autoloads); stdlib requires (`securerandom`, `strscan`) stay.

**B2. Autoload wiring.** Add `packs-rails` (or manual `config.autoload_paths`/
`config.eager_load_paths`) so `packs/dice_engine/lib` is Zeitwerk-managed and the
`FlowDice::*` constants autoload on reference.

**B3. Packwerk.** Add the `packwerk` gem, `bin/packwerk`, `packwerk.yml`, a root
`package.yml`, and `packs/dice_engine/package.yml` with:
- `enforce_dependencies: true`
- `enforce_privacy: true`
- public API limited to `FlowDice::Engine` (the only constant app code may touch)

`bin/packwerk check` must pass clean.

**B4. Spec reconciliation.** Engine specs now run under the app's RSpec (Zeitwerk
autoload via `rails_helper`). Configure `bundle exec rspec` to run both `spec/`
and `packs/**/spec/`. Remove the pack's standalone `Gemfile`, `Gemfile.lock`,
`.rspec`, and `spec_helper.rb`; the app's RSpec setup replaces them. The
`SequenceRng` test helper moves to a shared support location both layers can use.

## Section C — `POST /parse`

- Route: `post "/parse"`.
- `ParseController#create`: `FlowDice::Engine.parse(params.require(:notation))`.
  - Success → `200` JSON `{ notation:, plan:, explanation: }`, where `plan` is the
    serialized root node tree.
  - `FlowDice::ParseError` → `422` JSON `{ error: <message> }`.
- Request spec: one valid parse (asserts the plan tree + explanation) and one
  invalid notation (asserts 422 + error). 
- Minimal root route/page (placeholder "FlowDice") so the app boots to something;
  real views are #4–#6.

**Forward note (increment #3):** `render json:` emits string keys; the Ruby
evaluator reads symbol keys. The Opal/JS evaluator will reconcile symbol-vs-string
at that boundary — not solved here. `/parse`'s JSON shape (string keys) is the
established wire contract.

## Section D — Hotwire-Native readiness

- Confirm `turbo-rails` + `stimulus-rails` are present (from `rails new`).
- `turbo_native_app?` helper available for later conditional native UI.
- Standard Turbo Drive full-page navigation (no SPA); per-view routes arrive with
  the UI increments (#4 `/`, #6 `/favorites` + `/history`).

## Section E — `launch.json` + preview

- Write `.claude/launch.json`:
  ```json
  {
    "version": "0.0.1",
    "configurations": [
      { "name": "rails", "runtimeExecutable": "bin/dev", "runtimeArgs": [], "port": 3000 }
    ]
  }
  ```
- Then ask whether to `preview_start` the `rails` server. (Fulfills the deferred
  2026-06-13 dev-server request.)

## Section F — Testing / CI gates

- Full `bundle exec rspec` green: the 81 engine specs (now under Rails, after the
  version-spec removal) + the new `/parse` request specs.
- `bin/packwerk check` clean (no boundary violations).
- App boots (`bin/rails runner` / a smoke request spec hitting the root).

## Out of scope (later increments)

- Opal-compiled client evaluator + roll pipeline (#3).
- Calculator UI / text input (#4–#5).
- Favorites + Roll History (#6).
- PWA offline buildout — the `rails new` PWA stubs are kept but offline support is #7.
- Server-side persistence of app data — none in Phase 1 (DB present but unused).

## Risks

- **Engine restructuring (B1).** Renaming/splitting files and removing the require
  chain could break loading. Mitigation: the 82 engine specs run after each change;
  any regression surfaces immediately.
- **Zeitwerk gotchas.** `version.rb` (removed) and the `rng.rb`/`errors.rb` renames
  are the known conformance issues; addressed explicitly in B1.
