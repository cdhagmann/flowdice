# Opal-Compiled Evaluator + Parity — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compile the dice engine's evaluator to JavaScript via Opal and prove (with mini_racer) that it produces results identical to the Ruby evaluator across the golden fixtures.

**Architecture:** An Opal *entry* file (compile-only, never autoloaded) `require`s the evaluator subtree and exposes `FlowDice.evaluate(planJson, notation, rng) -> resultJson`. The wrapper JSON-parses the plan, symbolizes it (keys + enum string values, except `label`) to match the Ruby evaluator's symbol comparisons, adapts the injected JS RNG, evaluates, and returns the result as JSON. A mini_racer RSpec spec compiles the entry in-process and runs the golden fixtures through it, asserting JS == Ruby == fixture.

**Tech Stack:** Ruby 3.3 / Rails 8, RSpec, **Opal** (Ruby→JS compiler), **mini_racer** (embedded V8). The evaluator (`evaluator.rb`/`result.rb`/`parse_result.rb`) already exists and is "Opal-safe" by design.

**Working directory:** the repo root (a worktree of it at execution time). Run specs with `bundle exec rspec`.

> **Opal-API reality:** we have never run Opal on this project. The exact `Opal::Builder` invocation and the Ruby↔JS interop incantations below are a concrete best-effort. **Task 1 establishes the correct, working incantation via a smoke test; Tasks 2–3 reuse that exact pattern.** If an interop/build line differs for the installed Opal version, ADAPT it until the test passes — the assertions are the oracle. Do NOT weaken an assertion to make it pass. If `opal`/`mini_racer` cannot install or the smoke test cannot be made to pass, report BLOCKED.

---

## File Structure

```
packs/dice_engine/lib/flow_dice/opal/entry.rb   # NEW — compile-only entry + JS wrapper (Task 2)
spec/support/opal_evaluator_harness.rb          # NEW — compile + mini_racer + js_roll helper (Task 2)
spec/opal_smoke_spec.rb                          # NEW — toolchain smoke (Task 1)
packs/dice_engine/spec/flow_dice/opal_parity_spec.rb  # NEW — parity over GOLDEN_ROLLS (Task 3)
Gemfile                                          # + opal, mini_racer (Task 1)
```

Unchanged: `evaluator.rb`, `result.rb`, `parse_result.rb` (compiled as-is). The Ruby
evaluator is **not** modified.

---

## Task 1: Opal + mini_racer toolchain smoke test

De-risk first: prove the toolchain compiles Ruby→JS, runs it in V8, and supports Ruby↔JS interop — before touching the real evaluator.

**Files:**
- Modify: `Gemfile`
- Create: `spec/opal_smoke_spec.rb`

- [ ] **Step 1: Add the gems**

In `Gemfile`, inside `group :development, :test do ... end`:
```ruby
  gem "opal", "~> 1.8"
  gem "mini_racer", "~> 0.18"
```
Run: `bundle install`
(If those exact versions don't resolve with Ruby 3.3 / Rails 8.1, use the latest compatible releases and report which. `mini_racer` compiles a native V8 extension — if it fails to build, report BLOCKED with the error.)

- [ ] **Step 2: Write the smoke test**

`spec/opal_smoke_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"
require "opal"
require "mini_racer"

RSpec.describe "Opal + mini_racer toolchain" do
  it "compiles a Ruby method to JS and runs it in V8 with interop" do
    ruby = <<~RUBY
      module Smoke
        def self.add(a, b)
          a + b
        end
      end
      `self.Smoke = { add: function(a, b) { return #{Smoke.add(`a`, `b`)}; } }`
    RUBY

    builder = Opal::Builder.new
    builder.build_str("require 'opal'\n#{ruby}", "(smoke)")
    js = builder.to_s

    ctx = MiniRacer::Context.new
    ctx.eval(js)
    expect(ctx.eval("Smoke.add(40, 2)")).to eq(42)
  end
end
```

- [ ] **Step 3: Run it**

Run: `bundle exec rspec spec/opal_smoke_spec.rb`
Expected: `1 example, 0 failures`.
If it fails, the failure is in the Opal build call or the interop incantation — adjust them (e.g. `build_str` vs `build`, how the runtime is included, how `self`/global is referenced in V8) until the assertion (`42`) passes. Capture the WORKING build+interop pattern; Tasks 2–3 reuse it. If you cannot make it pass after genuine effort, report BLOCKED with what you tried.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "test(opal): add Opal + mini_racer toolchain smoke test"
```

---

## Task 2: Opal entry + wrapper + mini_racer harness

**Files:**
- Modify: `config/application.rb` (Zeitwerk-ignore the Opal-only dir)
- Create: `packs/dice_engine/lib/flow_dice/opal/entry.rb`
- Create: `spec/support/opal_evaluator_harness.rb`
- Create: `spec/flow_dice/opal_entry_spec.rb`

- [ ] **Step 1: Tell Zeitwerk to ignore the Opal-only directory (do this FIRST)**

The entry file (next step) contains backtick JS-interop (`` `self.FlowDice = …` ``). That is valid *Opal* source but, under MRI/Zeitwerk, backticks execute as **shell commands** — and the file's constant (`FlowDice::OpalEntry`) wouldn't match Zeitwerk's path expectation (`FlowDice::Opal::Entry`) anyway. The dir is under the autoload path, so Zeitwerk must ignore it. In `config/application.rb`, inside `class Application < Rails::Application` (after the `autoload_paths`/`eager_load_paths` lines added in increment #2):
```ruby
    # flow_dice/opal/ is Opal-only source (JS interop via backticks) compiled by
    # Opal, never loaded under MRI. Keep Zeitwerk away from it.
    Rails.autoloaders.main.ignore(root.join("packs/dice_engine/lib/flow_dice/opal"))
```

- [ ] **Step 2: Write the Opal entry + wrapper**

`packs/dice_engine/lib/flow_dice/opal/entry.rb`:
```ruby
# frozen_string_literal: true

# Compiled to JS by Opal. NOT autoloaded by Rails (lives under flow_dice/opal/,
# which is not on the autoload path). Carries explicit requires because Zeitwerk
# stripped the engine's require-chain — Opal's builder needs them. Deliberately
# does NOT require secure_random_rng (SecureRandom is unavailable in Opal); the
# RNG is injected from JS.
require "json"
require "flow_dice/result"
require "flow_dice/parse_result"
require "flow_dice/evaluator"

module FlowDice
  # Adapts a JS rng object (with int(min,max)) to the Ruby rng interface the
  # evaluator calls. `.to_i` guards against JS numbers arriving as floats.
  class JsRng
    def initialize(native)
      @native = native
    end

    def int(min, max)
      `#{@native}.int(#{min}, #{max})`.to_i
    end
  end

  module OpalEntry
    module_function

    # Recursively: symbolize hash keys; symbolize string values EXCEPT under :label
    # (label is display text and stays a String; type/op/die_kind/mode become symbols).
    def symbolize(node)
      case node
      when Hash
        node.each_with_object({}) do |(k, v), out|
          key = k.to_sym
          out[key] = key == :label ? v : symbolize(v)
        end
      when Array
        node.map { |e| symbolize(e) }
      when String
        node.to_sym
      else
        node
      end
    end

    # plan_json: JSON String; notation: String; js_rng: JS object with int(min,max).
    # Returns the result as a JSON String.
    def evaluate(plan_json, notation, js_rng)
      plan = symbolize(JSON.parse(plan_json))
      result = Evaluator.evaluate(
        ParseResult.new(notation, plan, nil),
        rng: JsRng.new(js_rng)
      )
      {
        kind: result.kind.to_s,
        total: result.total,
        notation: result.notation,
        dice: result.dice,
        breakdown: result.breakdown
      }.to_json
    end
  end
end

# Expose to JS. (Adjust this incantation to the working pattern Task 1 established.)
`
self.FlowDice = self.FlowDice || {};
self.FlowDice.evaluate = function(planJson, notation, rng) {
  return #{FlowDice::OpalEntry.evaluate(`planJson`, `notation`, `rng`)};
};
`
```

- [ ] **Step 3: Write the mini_racer harness (spec support)**

`spec/support/opal_evaluator_harness.rb`:
```ruby
# frozen_string_literal: true

require "opal"
require "mini_racer"

# Compiles the Opal evaluator entry once and runs rolls through it in V8.
module OpalEvaluatorHarness
  module_function

  # Compiled JS for the evaluator entry (memoized). Uses the build pattern that
  # Task 1's smoke test proved works for this Opal version.
  def compiled_js
    @compiled_js ||= begin
      Opal.append_path(Rails.root.join("packs/dice_engine/lib").to_s)
      builder = Opal::Builder.new
      builder.build("flow_dice/opal/entry")
      builder.to_s
    end
  end

  # A mini_racer context with FlowDice.evaluate loaded (fresh per call).
  def context
    ctx = MiniRacer::Context.new
    ctx.eval(compiled_js)
    ctx
  end

  # Roll `plan` (a Ruby plan hash) + `notation` through the JS evaluator with a
  # fixed RNG draw sequence. Returns the parsed result hash (string keys).
  def js_roll(plan, notation, rng_values, ctx: context())
    ctx.eval(<<~JS)
      globalThis.__seq = #{rng_values.to_json};
      globalThis.__rng = { int: function (min, max) { return globalThis.__seq.shift(); } };
    JS
    json = ctx.eval(
      "FlowDice.evaluate(#{plan.to_json.to_json}, #{notation.to_json}, globalThis.__rng)"
    )
    JSON.parse(json)
  end
end
```
(`plan.to_json.to_json` double-encodes so the plan JSON is passed as a JS string literal. If Task 1 showed globals must be referenced differently than `globalThis`, adjust here.)

- [ ] **Step 4: Write a spec proving the entry compiles, loads, and runs one roll**

`spec/flow_dice/opal_entry_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "FlowDice.evaluate (Opal-compiled)" do
  it "compiles to non-empty JS" do
    expect(OpalEvaluatorHarness.compiled_js).to be_a(String)
    expect(OpalEvaluatorHarness.compiled_js.length).to be > 100
  end

  it "exposes FlowDice.evaluate as a function" do
    ctx = OpalEvaluatorHarness.context
    expect(ctx.eval("typeof FlowDice.evaluate")).to eq("function")
  end

  it "evaluates a simple roll to a structured result" do
    plan = FlowDice::Engine.parse("3d6").plan
    result = OpalEvaluatorHarness.js_roll(plan, "3d6", [3, 5, 2])

    expect(result["kind"]).to eq("sum")
    expect(result["total"]).to eq(10)
    expect(result["notation"]).to eq("3d6")
    expect(result["dice"].map { |d| d["value"] }).to eq([3, 5, 2])
  end
end
```

- [ ] **Step 5: Run it**

Run: `bundle exec rspec spec/flow_dice/opal_entry_spec.rb`
Expected: `3 examples, 0 failures`.
If compilation raises, Opal cannot handle some construct in the evaluator subtree — read the error, identify the file/line, and adjust the EVALUATOR to an Opal-compatible equivalent **only if** it preserves identical Ruby behavior (then confirm the Ruby suite still passes in Step 5). Report any such change as a concern. If the result is wrong (not a compile error), it's likely the symbolize rule or the RNG adapter — fix those in `entry.rb`.

- [ ] **Step 6: Confirm the Ruby suite is unaffected**

Run: `bundle exec rspec packs/dice_engine/spec`
Expected: engine specs still green (`81 examples, 0 failures`) — the entry/harness are additive; the evaluator behavior is unchanged.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(opal): compile the evaluator to JS with a symbolizing JS entry"
```

---

## Task 3: Parity spec over the golden fixtures

**Files:**
- Create: `packs/dice_engine/spec/flow_dice/opal_parity_spec.rb`

- [ ] **Step 1: Write the parity spec**

`packs/dice_engine/spec/flow_dice/opal_parity_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"
require_relative "../fixtures/golden_rolls"

RSpec.describe "Opal/Ruby evaluator parity" do
  FlowDice::GOLDEN_ROLLS.each do |c|
    it "#{c[:notation]} (rng #{c[:rng].inspect}) matches Ruby and the fixture" do
      plan = FlowDice::Engine.parse(c[:notation]).plan

      ruby = FlowDice::Engine.roll(c[:notation], rng: FlowDice::SequenceRng.new(c[:rng].dup))
      js   = OpalEvaluatorHarness.js_roll(plan, c[:notation], c[:rng].dup)

      js_kept = js["dice"].select { |d| d["kept"] }.map { |d| d["value"] }

      # JS == fixture
      expect(js["total"]).to eq(c[:total])
      expect(js_kept).to eq(c[:kept])
      # JS == Ruby (full structural agreement on totals + kept values)
      expect(js["total"]).to eq(ruby.total)
      expect(js_kept).to eq(ruby.dice.select { |d| d[:kept] }.map { |d| d[:value] })
    end
  end

  it "agrees with Ruby on a percentile pair (symbolize boundary: die_kind/keep.mode)" do
    plan = FlowDice::Engine.parse("2d%kl").plan
    js = OpalEvaluatorHarness.js_roll(plan, "2d%kl", [7, 4, 3])
    expect(js["total"]).to eq(43)
    expect(js["dice"].map { |d| [d["die"], d["value"], d["kept"]] }).to eq([
      ["d%(tens)", 70, false], ["d%(tens)", 40, true], ["d%(units)", 3, true]
    ])
  end

  it "agrees with Ruby on a crit (symbolize boundary: op/mode symbols)" do
    plan = FlowDice::Engine.parse("d12C+5").plan
    js = OpalEvaluatorHarness.js_roll(plan, "d12C+5", [7])
    expect(js["total"]).to eq(24) # 12 (max d12) + 7 + 5
  end
end
```

- [ ] **Step 2: Run it**

Run: `bundle exec rspec packs/dice_engine/spec/flow_dice/opal_parity_spec.rb`
Expected: all examples pass (13 golden + 2 boundary = `15 examples, 0 failures`).
If a case mismatches: a JS-vs-Ruby divergence is a real parity bug — investigate (likely a symbolize gap, an RNG-coercion issue, or an Opal numeric/float quirk). Fix `entry.rb` (or the evaluator, preserving Ruby behavior). Do NOT relax the assertion.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "test(opal): assert JS/Ruby evaluator parity across the golden rolls"
```

---

## Final verification (after Task 3)

- [ ] `bundle exec rspec` → full suite green: 85 (Rails+engine) + 1 smoke + 3 entry + 15 parity = **104 examples, 0 failures**.
- [ ] `bin/packwerk check` → `No offenses detected` (the `opal/entry.rb` file lives in the pack; it references only `FlowDice::*` — no new cross-pack edges).
- [ ] `bin/rails zeitwerk:check` → `All is good!` (confirms the Task 2 Step 1 ignore correctly keeps Zeitwerk away from the compile-only `flow_dice/opal/` dir).

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| A — bundle (evaluator+result+parse_result; entry with explicit requires; exclude SecureRandomRng) | 2 |
| B — interop wrapper (FlowDice.evaluate; symbolize keys+enum-values-except-label; JsRng; result→JSON) | 2 |
| C — RNG injection (injectable; JS sequence-rng for parity) | 2 (harness), 3 |
| D — build (Opal::Builder in-process; no committed artifact) | 2 (harness) |
| E — parity test (GOLDEN_ROLLS via mini_racer; JS==Ruby==fixture; symbolize-boundary cases) | 3 |
| F — toolchain (opal+mini_racer gems; risk: Opal compile surprises, 85 Ruby specs as guardrail) | 1, 2 (Step 5) |

Out-of-scope items (pipeline/IndexedDB/fetch/browser-crypto-RNG/importmap-serving/UI) are intentionally absent — deferred to #4.

**Placeholder scan:** none. The "adapt the interop/build incantation" notes are deliberate (honest about a genuinely-new toolchain), each paired with a concrete best-effort + a test oracle — not vague hand-waving.

**Type/name consistency:** `FlowDice.evaluate(planJson, notation, rng)` and its `resultJson` shape (`kind`/`total`/`notation`/`dice`/`breakdown`) are consistent across `entry.rb`, the harness, and both specs; `OpalEvaluatorHarness.js_roll(plan, notation, rng_values)` signature matches its callers; `GOLDEN_ROLLS` keys (`notation`/`rng`/`total`/`kept`) match the fixture file from #1; `FlowDice::Engine.parse(...).plan`, `.roll`, and `FlowDice::SequenceRng` match prior increments.
