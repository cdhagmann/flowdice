# FlowDice — Architecture & Roadmap Design

- **Date:** 2026-06-13
- **Status:** Approved (design); first increment not yet planned
- **Source spec:** `knowledge/content/FlowDice/` (notation, mechanics, UI, platform docs)

## Overview

FlowDice is a fast, calculator-style dice roller for tabletop RPGs. No 3D
animations, no skeuomorphism — type or tap the notation, get the result, keep
playing. It ships as a Rails 8 + Hotwire PWA first, with Hotwire Native shells
planned for Phase 3. The notation language, mechanics, UI, and platform targets
are already specified in the knowledge vault; this document records the
**technical architecture and the full build roadmap** so that work can begin
without painting ourselves into a corner.

This is a greenfield project — the `flowdice` repo is empty.

## Goals

- Build the whole roadmap on **forward-compatible seams**: later phases add
  capability *additively*, never by rearchitecting.
- **Single source of truth** for dice logic — the engine exists as one Ruby
  codebase, reused everywhere (web, API, MCP, Discord, and — compiled — the
  browser).
- Offline-capable PWA for table use.

## Non-goals (per the roadmap's "Out of Scope")

- 3D dice animations, skeuomorphic UI.
- Probability calculator (AnyDice covers that).
- User accounts / social features in Phase 1 (revisited in Phase 3 for sync).
- Desktop native wrapper (the PWA covers desktop; a community Tauri-based
  "Hotwire Desktop" is a parked idea, not FlowDice scope).

## Key Architecture Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Server parses, client rolls.** Parsing (deterministic) is server-side Ruby; evaluation (random) runs client-side. | Splits at the one natural seam — parse has no randomness, evaluate is all randomness. |
| 2 | **The roll plan is a typed expression tree (JSON).** | Later mechanics (Flows, conditionals, named params) *add node types* rather than restructuring. |
| 3 | **Crit is always an evaluator node, never pre-resolved at parse time.** | Static `2d6c` and conditional `(n20?c)` share one code path — a static crit is just an always-true conditional. This is what stops Flows from forcing a rewrite. |
| 4 | **Engine is a pure-Ruby, Rails-free Packwerk pack** (`FlowDice::Engine`), *not* a separate gem. | Modular monolith: enforced boundary + narrow public API without gem ceremony. Extraction to a gem stays cheap if a standalone process ever needs it. |
| 5 | **RSpec + TDD.** | Expressive for the heavily data-driven notation tables. |
| 6 | **No server database in Phase 1.** Favorites/history live in IndexedDB. | The `/parse` endpoint is stateless; the first DB arrives only with accounts/cloud sync in Phase 3. |
| 7 | **Client evaluator is Opal-compiled from the same Ruby source.** | Literal single source of truth — zero semantic drift. Accepts the Opal runtime payload + a compile step. |
| 8 | **Offline = re-roll cached plans.** Typing a brand-new notation offline is out of scope for Phase 1. | Re-rolling favorites/history is the dominant table-side offline case. |
| 9 | **Client-side parsing is a sanctioned, no-rework future upgrade.** | Because the parser is the same Opal-compilable Ruby, shipping it client-side later gives full offline + zero round-trips with no code change — only incremental payload on top of the already-paid Opal runtime. |
| 10 | **Discord bot (Phase 2) uses `discordrb` (native Ruby).** | Stays one-language; the bot can `require` the engine directly, optionally skipping the MCP hop. (Verify current slash-command support when scoped.) |
| 11 | **Build Hotwire-Native-ready from day one** — a Phase 1 constraint, not a Phase 3 feature. | The Rails app *is* the native app; Phase 3 shells only wrap it. Diverging from the conventions now (especially URL-per-view navigation) forces rework later. See the Hotwire Native readiness section. |

### Rejected alternatives

- **Hand-written JS evaluator** — leaner payload but a second implementation to
  keep in sync; rejected in favor of Opal single-source.
- **ruby.wasm whole-engine client-side** — heavy multi-MB payload, overkill for
  Phase 1; kept as a theoretical fallback only.
- **Opal for the Discord bot** — pain: `discord.js` is async JS-native and would
  require pervasive interop, with no engine-reuse benefit (the bot is a thin
  client). `discordrb` is the right "stay in Ruby" answer.
- **Standalone engine gem now** — premature ceremony; Packwerk gives the
  boundary today.

## Section A — Engine & roll-plan format

Two phases, one seam:

- `FlowDice::Engine.parse(notation)` → **roll plan** (typed tree, JSON) +
  explanation text. Pure, deterministic, server-side.
- `evaluate(plan, rng, params)` → **result** (total, per-die values,
  kept/dropped). The random part. Runs natively in Ruby (API/MCP/Discord) and,
  via Opal, in the browser. The **parser is never duplicated**. The `params`
  argument (active named-parameter toggles) is the single mechanism powering
  named-parameter selection everywhere — web long-press, Discord buttons, and the
  MCP `roll_flow` tool all just pass `params` to the same evaluator.

The engine splits internally into `parser` / `evaluator` / `explanation` over a
shared `plan` definition, so Opal can compile **just the evaluator subtree (+
plan defs)** without dragging the parser along.

### Plan node types

Phase 1 core uses a subset; later phases *add* node types.

| Node | Introduced | Purpose |
|------|-----------|---------|
| `dice` | core | `{die_kind: standard\|custom\|percentile, faces, count, keep?}` |
| `const` | core | flat `+N` / `-N` operand |
| `binary` | core | `+` / `−` |
| `crit` | core | `{mode: normal\|perkins, child}` — evaluator node, never pre-resolved |
| `conditional` | stretch | `{trigger, then, else?}` |
| `trigger` | stretch | `{kind: natural\|total\|param\|inherited, match: value\|set\|range\|name, ref?}` |
| `flow` | stretch | `{segments:[…]}`; later segments reference earlier rolls |
| `params` | stretch | declared named params, surfaced at plan top for UI toggles |

**Reserved for later, designed-for now:** Phase 2 mechanics are additive on this
same tree. Reroll (`R`/`r`) and explode (`!`/`!!`/`!p`) become per-`dice`
attributes — reroll binds to the *individual* die (e.g. `4(d6R[1..2])kh3`), so the
grammar/tokenizer reserves these symbols from day one to avoid a redesign.
Success/failure counting changes the *result kind* (see Result shape). Fate `dF`
is just sugar for `d{-1,0,1}`, already expressible.

### Examples

`2d20kh+5` (core):

```json
{ "type": "binary", "op": "+",
  "left":  { "type": "dice", "die_kind": "standard", "faces": 20, "count": 2,
             "keep": { "mode": "high", "n": 1 } },
  "right": { "type": "const", "value": 5 } }
```

`d20+5 -> d8(n20?c)+3` (stretch — same core nodes, now wrapped):

```json
{ "type": "flow", "segments": [
  { "expr": { "type": "binary", "op":"+",
              "left": {"type":"dice","faces":20,"count":1},
              "right": {"type":"const","value":5} } },
  { "expr": { "type": "binary", "op":"+",
      "left": { "type": "conditional",
                "trigger": { "kind":"natural", "match":20, "ref":"segment[0]" },
                "then":  { "type":"crit", "mode":"normal", "child": {"type":"dice","faces":8,"count":1} },
                "else":  { "type":"dice","faces":8,"count":1 } },
      "right": { "type":"const","value":3 } } } ] }
```

### Result shape

```json
{ "kind": "sum", "total": 23, "notation": "2d20kh+5",
  "dice": [ {"die":"d20","value":18,"kept":true}, {"die":"d20","value":7,"kept":false} ],
  "breakdown": "18 (kept), 7 (dropped), +5 = 23" }
```

Percentile pairs carry their components in `dice`/`breakdown` (e.g.
`"70 + 3 = 73"`), per the spec's `d%` display rules.

**The result is designed to grow beyond a numeric `total`.** Phase 2 success/
failure counting (e.g. `8d6>=4` → "5 successes") returns a *count*, not a sum,
and exploding dice produce per-die roll chains. So a result carries a `kind`
(`sum` in Phase 1) and may later add `successes`/`failures` and nested per-die
rolls — without breaking the `/parse`→evaluate→display contract.

### Mechanics notes (from the spec)

- `d[a..b]` is normalized to explicit faces at parse time; `d{…}` is an explicit
  set. The evaluator only ever picks uniformly from a face list.
- `d%` is a linked tens+units pair with the **00+0=100** rule; `kh`/`kl` on `d%`
  operates on the tens die only (units fixed) — distinct from flat `d100`.
- Normal crit `c` doubles dice count; Perkins crit `C` maxes one set + rolls
  again (`2d6C` → `12 + 2d6`). Static modifiers stay outside crit scope. **Crit
  scope = whatever subtree the parentheses wrap** — the `crit` node sits above
  that subtree, so `(d8(<smite>?+2d8))(n20?c)+3` (crit both weapon and smite
  dice, not the +3) falls out of the tree structure for free.
- RNG: native Ruby uses `SecureRandom`; the browser uses
  `crypto.getRandomValues()` (also a CSPRNG), injected into the Opal evaluator.

## Section B — Repo & app structure

Modular monolith, one repo, Rails 8, RSpec, no server DB in Phase 1, engine as a
Packwerk pack whose only public boundary is `FlowDice::Engine`.

```
flowdice/
  packs/dice_engine/              # Packwerk pack — pure Ruby, ZERO Rails deps
    package.yml                   #   public API: FlowDice::Engine only
    lib/flow_dice/
      engine.rb                   #   façade: .parse / .evaluate / .explain
      plan/                       #   plan node data structures  ─┐ compiled
      evaluator/                  #   plan + rng -> result        ─┴─ to JS via Opal
      parser/                     #   notation -> plan (server now; Opal-flippable)
      explanation/                #   plan -> plain English
    spec/                         #   RSpec + golden fixtures (run vs Ruby AND Opal-JS)
  app/
    controllers/parse_controller.rb       # POST /parse -> {plan, explanation}
    javascript/
      controllers/calculator_controller.js  # Stimulus
      flow_dice/                             # Opal-compiled evaluator (built artifact)
      roll_pipeline.js                       # plan cache + RNG + evaluate glue
    views/…                                  # mobile-first, Turbo Drive
  bin/build_opal                  # compiles evaluator subtree -> app/javascript/flow_dice
  public/manifest.json  +  service worker
  bot/                            # (Phase 2) discordrb — requires packs/dice_engine
```

## Section C — Client, offline & PWA

1. **`POST /parse`** → `{ plan, explanation }`. Stateless; the canonical
   contract and the basis of the future JSON API.
2. **`roll_pipeline.js`** — on a notation: look up the plan in the **IndexedDB
   cache** (keyed by notation string); on miss, call `/parse` and cache it. Then
   call the **Opal-compiled evaluator** with an RNG shim backed by
   `crypto.getRandomValues()`. The plan→result boundary is the *only* Opal
   interop surface (thin).
3. **Stimulus `calculator_controller`** builds the notation from buttons, shows
   live notation + explanation, disables invalid buttons, fires the pipeline,
   renders the result popup. **Text-input mode** is the same pipeline over a
   typed string.
4. **Favorites & history** — IndexedDB, offline-first; tap-to-reroll replays a
   cached plan.
5. **Service worker** caches the app shell **including the Opal bundle**, so
   re-rolls work fully offline. Installable via the web app manifest.
6. **CI parity** — golden fixtures run against both the native Ruby evaluator
   and the Opal-compiled artifact, catching compilation / RNG-injection / float
   quirks (not semantic drift, since it is one source).

The browser, PWA, and Phase 3 Hotwire Native webviews all run the **same Opal
evaluator**. The one exception is **Android Auto** (Phase 3 stretch): its
`androidx.car.app` UI has no WebView, so it's a separate Kotlin module that rolls
via the **JSON API** (server-side Ruby evaluator). That is the concrete reason
the stateless `/parse`-and-roll JSON contract is a real, first-class interface —
not just an internal detail.

Navigation uses standard Turbo Drive full-page navigation (not heavy Turbo
Frames) for Hotwire Native readiness — see the next section.

## Section D — Hotwire Native readiness

FlowDice's defining platform bet: **the Rails app *is* the app** — one codebase
serves browser, PWA, and (Phase 3) native iOS/Android. The native shells only
wrap the web content in a WebView with a platform-native navigation stack. That
only works if Phase 1 is built to the right conventions from day one; diverging
now forces rework later.

### Phase 1 constraints (binding on increments #2, #4–#7)

- **Mobile-first responsive CSS** — one-handed portrait use, thumb-reachable
  controls (per the UI Reference).
- **URL-based navigation via standard Turbo Drive** — *not* heavy Turbo Frames
  for primary flows.
- **Each top-level view is its own route** so it maps cleanly to a native
  navigation/tab stack: `/` (calculator / dice bag), `/favorites`, `/history`.
  These are real Turbo Drive page navigations, **not** client-side tab-swapping
  inside one page. (Favorites/history routes render a shell that Stimulus
  populates from IndexedDB, since there is no server DB in Phase 1.)
- **`turbo_native_app?` helper available** for conditional native-only UI.
- **`turbo-rails` + `stimulus-rails`** as the Hotwire foundation.
- Service worker for offline (increment #7) — also benefits the WebView.

The Opal evaluator + service worker run inside the WebView too, so client-side
rolling and offline re-rolls work natively with **no third roller**.

### Phase 3 shells (added later, no web rework)

- iOS shell — Swift / Xcode, `hotwire-native-ios` Swift Package.
- Android shell — Kotlin / Android Studio, `hotwire-native-android` Gradle dep.
- `hotwire-native-bridge` (JS) + bridge components for native toolbar buttons /
  modals.
- **Path configuration JSON** mapping URLs → native screens.
- Native screens only where high fidelity is needed (sound, haptics, TTS).

Desktop stays PWA-only — Hotwire Native targets iOS/Android only.

## Section E — Roadmap (each item = its own spec → plan → build cycle)

### Phase 1 — Core MVP

1. **Engine** — parser + plan tree + Ruby evaluator + explanation; core notation
   only (standard / custom / `d%` / `d100` dice, `kh`/`kl`, `c`/`C`, `+`/`−`);
   RSpec TDD + golden fixtures. Fixtures must include Chris's **Custom Skill
   System** (`4d[0..5]`, `6d[0..5]kh4`, `…kl4`) — already fully expressible in
   core via range-faces + keep, and a use case that matters personally.
   **Foundation — first thing built.**
2. **Rails skeleton + `/parse`** — app, Packwerk, engine wired, seam working
   end-to-end.
3. **Opal evaluator + roll pipeline** — compile, RNG shim, plan cache, parity CI.
4. **Calculator UI** — the `/` route; Stimulus, color-coded buttons, result
   popup. *(Visual increment — offer the visual companion / mockups when scoping
   it.)*
5. **Text input mode.**
6. **Favorites & Roll History** — `/favorites` and `/history` routes (distinct
   URLs for Hotwire Native readiness); IndexedDB-backed.
7. **PWA / offline** — manifest, service worker, installable, offline re-rolls
   verified. *Candidate service-worker gem:* `coldwire-rails` — see
   `docs/superpowers/specs/2026-09-12-coldwire-rails-evaluation.md` (evaluated,
   not adopted; pin `~> 0.3.0` and re-check maturity when scoping).

### Phase 1 — Stretch

8. **Live explanations** (UX polish; the engine already emits the text).
9. **Flows + conditionals + triggers** — parser/`plan` gain
   `flow`/`conditional`/`trigger` nodes; evaluator does stateful
   segment-by-segment rolling; multi-box modal UI. *(Where crit-as-node pays
   off.)*
10. **Named parameters** — `<name>` / `s<name>`, plan surfaces declarations,
    long-press toggles on favorites.
11. **Basic MCP server** — `roll` / `parse` tools over the same engine.

### Phase 2 — Advanced dice & integrations

Exploding / reroll / penetrating dice, success counting (returns a success/
failure *count*, not a sum — see Result shape), Fate dice (engine = new node
types/flags/result kinds); full MCP server; Template Library; favorites grouped
by category; **discordrb** bot (requires the engine directly); Natural Language
Input (on-device LLM — WebLLM/Transformers.js + WebGPU on web, platform models on
native — with a rules-based fallback; model cached for offline).

### Phase 3 — Native & characters

Characters (a notation-*generation* layer feeding the same parser; MVP scope is
D&D 5e only, custom systems deferred) + accounts + OAuth + cloud sync (**first
server DB**); Hotwire Native iOS/Android shells (wrap the PWA — see Section D; the
same Opal evaluator runs in the webview, so no third roller); sound / TTS /
haptics; push & shared rolls (stretch); **Android Auto** (stretch — a *separate*
Kotlin `androidx.car.app` module, no WebView, talks to the JSON API).

**Seam guarantee:** every later item is additive — new plan node types, the same
single-source engine, native wraps the PWA, characters generate notation, and
the first database appears only at Phase 3 sync.

## Open / deferred decisions

- **Client-parse flip timing** — when (if ever) to ship the parser in the Opal
  bundle for full offline. No rework either way.
- **MCP hosting model** — in-process with Rails vs. a standalone Ruby process
  (decided when increment #11 is scoped).
- **Accounts / auth provider** — Phase 3, with cloud sync.
- **`discordrb` slash-command maturity** — verify current state before
  committing in Phase 2.
- **Reroll operators (`R`/`r`)** — grammar-reserved but Phase 2; excluded from
  Phase 1.
- **Native-WebView offline strategy** — service worker vs. native-layer caching
  (WKWebView service-worker support has caveats); decided when the Phase 3
  shells are scoped. The #7 candidate `coldwire-rails` targets exactly this
  (200 fallback that boots Turbo, Turbo-Frame answers, Android UA cookie, iOS
  app-bound domains) — see the 2026-09-12 evaluation.
- **Path configuration JSON** (URL → native screen map) — authored in Phase 3.

## References

All source docs under `knowledge/content/FlowDice/` were reviewed for this design.

- **Top-level:** `Architecture.md`, `Roadmap.md`, `Pitch.md`, `FlowDice.md`,
  `Gaps.md`, `Phase 1 Features.md` (stub), `index.md`, `d%.md` (stub)
- **Specification/** — `Notation Spec.md` (full grammar), `Crit Mechanics.md`,
  `Normal Crit.md`, `Perkins Crit.md`, `Keep Highest and Lowest.md`,
  `Percentile Pair.md`, `d% vs d100.md`, `Custom Face Values.md`, `Flows.md`,
  `Named Parameters.md`, `Natural and Total Triggers.md`, `Reroll Mechanic.md`
  (Phase 2), `Exploding Dice.md` (Phase 2), `Success and Failure Counting.md`
  (Phase 2, notation TBD), `Fate Dice.md` (Phase 2), `Custom Sound Effects.md`
  (Phase 3)
- **Interface/** — `Calculator UI.md`, `UI Reference.md`, `Text Input.md`,
  `Favorites.md`, `Roll History.md`, `Human-Readable Explanations.md`,
  `Template Library.md` (Phase 2), `Natural Language Input.md` (Phase 2),
  `Characters.md` (Phase 3)
- **Platform/** — `PWA.md`, `Hotwire Native.md`, `MCP Server.md`,
  `Discord Bot.md` (note: source assumes Node + discord.js; **superseded** by
  decision #10 → `discordrb`), `Android Auto.md` (Phase 3 stretch),
  `Hotwire Desktop Idea.md` (parked, out of scope)
- **Reference/** — `CritDice.md` (inspiration), `Custom Skill System.md`
  (Chris's homebrew — Phase 1-supported via `d[0..5]` + keep)
