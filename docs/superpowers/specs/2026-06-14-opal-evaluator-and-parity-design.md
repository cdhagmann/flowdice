# Increment #3 — Opal-Compiled Evaluator + Parity Design

- **Date:** 2026-06-14
- **Status:** Approved (design)
- **Parent design:** `docs/superpowers/specs/2026-06-13-flowdice-architecture-and-roadmap-design.md`
- **Builds on:** #1 (engine) + #2 (Rails app + `/parse`), on `main` at `be15f3b`.

## Goal

Compile the dice engine's **evaluator** to JavaScript via Opal and prove
*automatically* that the compiled JS produces results identical to the Ruby
evaluator across the golden fixtures. This is the single-source-of-truth payoff:
one Ruby evaluator, run natively server-side and compiled to JS client-side.

## Scope

**In:** compile the evaluator subtree to JS; a JS-callable entry function with the
symbol-key boundary wrapper and injectable RNG; a mini_racer parity spec.
**Out (→ #4):** the IndexedDB plan-cache, `fetch('/parse')`, the browser
`crypto.getRandomValues` RNG, importmap-serving the compiled JS, and any UI. The
roll *pipeline* has no consumer or browser test harness until the calculator UI.

## Decisions

| # | Decision | Notes |
|---|----------|-------|
| 1 | **Evaluator + parity only** | Defer the roll pipeline (IndexedDB/fetch) to #4 where the UI drives it and a browser harness can test it. |
| 2 | **Parity via `mini_racer`** (embedded V8) | An RSpec spec runs the compiled JS in-process; no Node toolchain, no browser. |
| 3 | **Exclude `SecureRandomRng`** from the bundle | `securerandom` isn't in Opal; the RNG is injected from JS. |
| 4 | **Symbolize at the JS boundary** | `/parse` JSON has string keys/values; the Ruby evaluator compares symbols. The wrapper converts; the evaluator is untouched. |
| 5 | **Compile in-process for the parity spec** | `Opal::Builder` from Ruby; no committed JS artifact yet (that's #4's importmap concern). |

## Section A — What compiles (the Opal bundle)

The evaluator subtree only:

- `packs/dice_engine/lib/flow_dice/evaluator.rb` (the logic)
- `packs/dice_engine/lib/flow_dice/result.rb` (`FlowDice::Result`)
- `packs/dice_engine/lib/flow_dice/parse_result.rb` (`FlowDice::ParseResult`)

A new **Opal entry file** `packs/dice_engine/lib/flow_dice/opal/entry.rb` is used
*only* for Opal compilation (never autoloaded by Rails). Because Zeitwerk removed
the require-chain, this file carries explicit `require`s so Opal's builder knows
what to bundle:

```ruby
require "flow_dice/result"
require "flow_dice/parse_result"
require "flow_dice/evaluator"
```

It does **not** require `secure_random_rng` (excluded), `plan`, `parser`, or
`explanation` (not needed by the evaluator). Opal's corelib supplies `Struct`,
`Hash`, `Array`, `Integer`, `Symbol`, and the enumerable methods the evaluator
uses (`sort_by`, `each_with_index`, `last`, `first`, `include?`, `merge`, `zero?`).

## Section B — Interop wrapper

The entry file defines a JS-callable function:

```
FlowDice.evaluate(planObj, notation, rng) -> resultObj
```

The Ruby wrapper (`FlowDice::OpalEntry.evaluate`) does three things:

1. **Symbolize the incoming plan.** `/parse` emits string keys *and* string enum
   values (`{"type":"binary","op":"+","die_kind":"standard","keep":{"mode":"high","n":1}}`),
   but the evaluator compares symbols (`node[:type] == :dice`, `node[:op] == :+`,
   `keep[:mode] == :high`, `die_kind == :percentile`). Rule: **recursively
   symbolize all hash keys, and symbolize every string value EXCEPT the value
   under a `label` key** (`label` is display text and stays a string;
   `type`/`op`/`die_kind`/`mode` become symbols, e.g. `"+" → :+`). Integers
   (`faces`, `count`, `n`, `value`) and arrays (`faces` lists) pass through;
   nested nodes (`left`/`right`/`child`/`keep`) recurse.
2. **Wrap the injected RNG** so Ruby's `rng.int(min, max)` calls the JS rng's
   `int`.
3. **Evaluate and convert back.** Build `ParseResult.new(notation, plan, nil)`,
   call `Evaluator.evaluate(pr, rng:)`, then convert the `Result` struct to a plain
   JS object: `{ kind, total, notation, dice: [{die, value, kept}, …], breakdown }`
   (`kind` symbol → string).

The Ruby evaluator is **not modified** — it still serves native server-side
rolling (MCP/Discord, later).

## Section C — RNG injection

`FlowDice.evaluate` takes an `rng` exposing `int(min, max)` (inclusive). For #3's
parity tests we inject a **JS sequence-RNG** that returns the fixture's exact draw
sequence in order — mirroring the Ruby `SequenceRng` — so identical draws produce
identical results. The browser `crypto.getRandomValues`-backed RNG is built with
the pipeline in **#4**.

## Section D — Build mechanism

Compile with `Opal::Builder` (Ruby API), load path = `packs/dice_engine/lib`,
entry = `flow_dice/opal/entry`. For #3 the **parity spec compiles in-process** and
hands the JS string to a mini_racer context — no committed artifact. Producing a
served/pinned JS file (importmap) is deferred to #4.

## Section E — Parity test (the deliverable)

A spec (`packs/dice_engine/spec/flow_dice/opal_parity_spec.rb`, run under
`rails_helper`) reusing the existing `FlowDice::GOLDEN_ROLLS`:

1. Compile the Opal entry once (in-process) and load it into a mini_racer context;
   define a JS sequence-RNG factory in that context.
2. For each fixture `{notation, rng, total, kept}`:
   - Ruby side: `plan = FlowDice::Engine.parse(notation).plan`;
     `ruby = FlowDice::Engine.roll(notation, rng: SequenceRng.new(rng))`.
   - JS side: serialize `plan` to JSON; call
     `FlowDice.evaluate(plan, notation, jsSeqRng(rng))` in mini_racer.
   - Assert the JS result's `total` and kept values equal **both** the Ruby
     result **and** the fixture's `total`/`kept`.
3. Include cases that exercise the symbolize boundary explicitly: a binary+crit
   (`op`/`mode` symbols), a `d%` (percentile + `keep.mode`), and a custom-face
   die (`faces` array preserved, `label` preserved).

This proves **JS evaluator == Ruby evaluator == fixture** for every golden case.

## Section F — Toolchain & risk

- Add gems: `opal` and `mini_racer` (`mini_racer` builds a native V8 extension).
- **Primary risk:** the evaluator has never actually been compiled by Opal — it
  may use a construct Opal handles differently. The parity spec is exactly where
  that surfaces. If Opal balks, adjust the evaluator to a compatible form **while
  keeping the 85 Ruby specs green** (the regression guardrail). Any such change
  must preserve identical Ruby behavior.
- If `opal` or `mini_racer` cannot install in this environment, that's a hard
  blocker to surface (not work around).

## Out of scope (→ increment #4)

- Roll pipeline: IndexedDB plan-cache keyed by notation, `fetch('/parse')` on miss.
- Browser `crypto.getRandomValues` RNG adapter.
- Importmap-pinning/serving the compiled evaluator JS (a committed build artifact +
  a `bin/build_opal`/rake task + a CI freshness check).
- Stimulus controller / calculator UI.

## Forward note

When Flows (Phase 1 stretch) add `conditional`/`trigger`/`flow` nodes with new
string-valued fields, extend the symbolize rule's enum set accordingly. The core
rule ("symbolize keys + string values except `label`") already covers the Phase 1
core node schema.
