# Dice Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `FlowDice::Engine` — a pure-Ruby dice-notation parser, evaluator, and explanation generator for FlowDice Phase 1 core notation.

**Architecture:** Two phases over a shared plan representation. `parse(notation)` produces a typed expression tree (plain symbol-keyed hashes) plus an English explanation; `evaluate(plan, rng:)` walks the tree against an injected RNG and returns a structured result. Plan nodes and the evaluator are written in plain, Opal-safe Ruby (no fancy stdlib) because the evaluator is later compiled to JS via Opal; the parser and explanation generator stay server-side and may use any Ruby (e.g. `StringScanner`).

**Tech Stack:** Ruby 3.3+, RSpec, `securerandom`, `strscan` (stdlib).

**Scope (Phase 1 core notation only):** standard dice `NdX`/`dX`, custom faces `d{…}`, ranges `d[a..b]`, percentile pair `d%`, flat `d100`, keep `kh`/`kl` (default N=1), normal crit `c`, Perkins crit `C`, flat modifiers `+N`/`-N`. **Out of scope (later increments):** Flows (`->`), conditionals/triggers, named parameters, reroll (`R`/`r`), exploding (`!`), success counting, parenthesized grouping.

**Working directory:** All commands run from `packs/dice_engine/` unless noted. Git commands work from anywhere in the repo. Implementation should happen on a feature branch / worktree (the execution skill handles isolation).

---

## File Structure

```
packs/dice_engine/
  Gemfile                         # standalone dev harness: rspec only (reconciled with Rails + Packwerk in increment #2)
  .rspec                          # --require spec_helper --format documentation
  .gitignore                      # .bundle/, vendor/bundle, Gemfile.lock optional
  lib/
    flow_dice.rb                  # entrypoint: requires all engine files
    flow_dice/
      version.rb                  # VERSION constant
      errors.rb                   # ParseError
      rng.rb                      # SecureRandomRng (#int(min,max))  [Opal-safe]
      plan.rb                     # node builder functions            [Opal-safe]
      parser.rb                   # notation String -> plan tree (StringScanner; server-side)
      evaluator.rb                # plan + rng -> Result              [Opal-safe]
      explanation.rb              # plan -> English String (server-side)
      engine.rb                   # façade: parse / evaluate / explain / roll
  spec/
    spec_helper.rb                # load path + require flow_dice + support
    support/
      sequence_rng.rb             # deterministic test RNG
    flow_dice/
      rng_spec.rb
      plan_spec.rb
      parser_spec.rb
      evaluator_spec.rb
      explanation_spec.rb
      engine_spec.rb
      fixtures_spec.rb            # golden fixtures (incl. Custom Skill System)
    fixtures/
      golden_rolls.rb             # [{notation, rng, expected}] data
```

**Plan node shapes (the contract every task depends on):**

```ruby
# dice
{ type: :dice, die_kind: :standard|:custom|:percentile,
  faces: Integer | Array<Integer>,   # Integer for standard (X) & percentile (100); Array for custom
  count: Integer,                      # number of dice (tens dice, for percentile)
  keep: nil | { mode: :high|:low, n: Integer },
  label: String }                      # source die token, e.g. "d20", "d[0..5]", "d%", for display
# const
{ type: :const, value: Integer }
# binary
{ type: :binary, op: :+|:-, left: <node>, right: <node> }
# crit  (always wraps a dice node in Phase 1)
{ type: :crit, mode: :normal|:perkins, child: <node> }
```

**`ParseResult`** = `Struct.new(:notation, :plan, :explanation)` (`.plan` is the root node).
**`Result`** = `Struct.new(:kind, :total, :notation, :dice, :breakdown)` where `dice` is `Array<{die:String, value:Integer, kept:Boolean}>`.

> **Display note:** the structured `dice` array (with `kept` flags, values, and tens/units for `d%`) is the source of truth the UI renders from. `breakdown` is a plain convenience string; rich display formatting (interleaving modifiers, bolding kept dice, the `d%` "70 + 3 = 73" form) is the UI increment's job, not the engine's.

---

## Task 1: Pack skeleton & RSpec harness

**Files:**
- Create: `packs/dice_engine/Gemfile`
- Create: `packs/dice_engine/.rspec`
- Create: `packs/dice_engine/.gitignore`
- Create: `packs/dice_engine/lib/flow_dice.rb`
- Create: `packs/dice_engine/lib/flow_dice/version.rb`
- Create: `packs/dice_engine/spec/spec_helper.rb`
- Create: `packs/dice_engine/spec/flow_dice/version_spec.rb`

- [ ] **Step 1: Create the Gemfile**

`packs/dice_engine/Gemfile`:
```ruby
# frozen_string_literal: true

source "https://rubygems.org"

gem "rspec", "~> 3.13"
```

- [ ] **Step 2: Create `.rspec` and `.gitignore`**

`packs/dice_engine/.rspec`:
```
--require spec_helper
--format documentation
```

`packs/dice_engine/.gitignore`:
```
/.bundle/
/vendor/bundle
```

- [ ] **Step 3: Create the entrypoint and version**

`packs/dice_engine/lib/flow_dice/version.rb`:
```ruby
# frozen_string_literal: true

module FlowDice
  VERSION = "0.1.0"
end
```

`packs/dice_engine/lib/flow_dice.rb`:
```ruby
# frozen_string_literal: true

require_relative "flow_dice/version"
```

- [ ] **Step 4: Create the spec helper and a trivial version spec**

`packs/dice_engine/spec/spec_helper.rb`:
```ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "flow_dice"

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
end
```

`packs/dice_engine/spec/flow_dice/version_spec.rb`:
```ruby
# frozen_string_literal: true

RSpec.describe FlowDice do
  it "has a version" do
    expect(FlowDice::VERSION).to eq("0.1.0")
  end
end
```

- [ ] **Step 5: Install and run**

Run: `bundle install`
Then: `bundle exec rspec`
Expected: `1 example, 0 failures`

- [ ] **Step 6: Commit**

```bash
git add packs/dice_engine
git commit -m "feat(engine): scaffold dice_engine pack with rspec harness"
```

---

## Task 2: RNG abstraction

**Files:**
- Create: `packs/dice_engine/lib/flow_dice/rng.rb`
- Create: `packs/dice_engine/spec/support/sequence_rng.rb`
- Create: `packs/dice_engine/spec/flow_dice/rng_spec.rb`
- Modify: `packs/dice_engine/lib/flow_dice.rb`

The RNG interface is a single method `#int(min, max)` returning a uniform integer in the inclusive range `[min, max]`. Production uses `SecureRandom`; tests use a deterministic `SequenceRng` that also asserts each drawn value is in range (catching evaluator range bugs).

- [ ] **Step 1: Write the failing test**

`packs/dice_engine/spec/flow_dice/rng_spec.rb`:
```ruby
# frozen_string_literal: true

RSpec.describe FlowDice::SecureRandomRng do
  subject(:rng) { described_class.new }

  it "returns integers within the inclusive range" do
    200.times do
      v = rng.int(1, 6)
      expect(v).to be_between(1, 6)
    end
  end

  it "can return the only value when min == max" do
    expect(rng.int(4, 4)).to eq(4)
  end

  it "raises when min > max" do
    expect { rng.int(6, 1) }.to raise_error(ArgumentError)
  end

  it "covers both endpoints over many draws" do
    seen = Array.new(2000) { rng.int(0, 1) }.uniq.sort
    expect(seen).to eq([0, 1])
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/flow_dice/rng_spec.rb`
Expected: FAIL — `uninitialized constant FlowDice::SecureRandomRng`

- [ ] **Step 3: Implement the RNG**

`packs/dice_engine/lib/flow_dice/rng.rb`:
```ruby
# frozen_string_literal: true

require "securerandom"

module FlowDice
  # Cryptographically secure RNG. The browser supplies an equivalent backed by
  # crypto.getRandomValues() in the Opal evaluator (increment #3).
  class SecureRandomRng
    # Uniform integer in the inclusive range [min, max].
    def int(min, max)
      raise ArgumentError, "min (#{min}) > max (#{max})" if min > max

      min + SecureRandom.random_number(max - min + 1)
    end
  end
end
```

Add to `packs/dice_engine/lib/flow_dice.rb` (after the version require):
```ruby
require_relative "flow_dice/rng"
```

- [ ] **Step 4: Add the test-support SequenceRng**

`packs/dice_engine/spec/support/sequence_rng.rb`:
```ruby
# frozen_string_literal: true

module FlowDice
  # Deterministic RNG for tests. Returns queued values in order and asserts
  # each is within the requested [min, max] range.
  class SequenceRng
    def initialize(values)
      @values = values.dup
    end

    def int(min, max)
      raise "SequenceRng exhausted" if @values.empty?

      v = @values.shift
      unless (min..max).cover?(v)
        raise "SequenceRng value #{v} out of range [#{min}, #{max}]"
      end
      v
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/flow_dice/rng_spec.rb`
Expected: PASS — `4 examples, 0 failures`

- [ ] **Step 6: Commit**

```bash
git add packs/dice_engine
git commit -m "feat(engine): add SecureRandomRng and SequenceRng test helper"
```

---

## Task 3: Plan node builders

**Files:**
- Create: `packs/dice_engine/lib/flow_dice/plan.rb`
- Create: `packs/dice_engine/spec/flow_dice/plan_spec.rb`
- Modify: `packs/dice_engine/lib/flow_dice.rb`

`Plan` centralizes node shapes so the parser and evaluator agree. Nodes are plain symbol-keyed hashes (Opal-safe, JSON-serializable).

- [ ] **Step 1: Write the failing test**

`packs/dice_engine/spec/flow_dice/plan_spec.rb`:
```ruby
# frozen_string_literal: true

RSpec.describe FlowDice::Plan do
  it "builds a dice node with defaults" do
    node = described_class.dice(die_kind: :standard, faces: 20, count: 2, label: "d20")
    expect(node).to eq(
      type: :dice, die_kind: :standard, faces: 20, count: 2, keep: nil, label: "d20"
    )
  end

  it "builds a dice node with a keep clause" do
    node = described_class.dice(
      die_kind: :standard, faces: 20, count: 2, label: "d20",
      keep: { mode: :high, n: 1 }
    )
    expect(node[:keep]).to eq(mode: :high, n: 1)
  end

  it "builds const, binary, and crit nodes" do
    c = described_class.const(5)
    b = described_class.binary(:+, c, c)
    k = described_class.crit(:normal, c)

    expect(c).to eq(type: :const, value: 5)
    expect(b).to eq(type: :binary, op: :+, left: c, right: c)
    expect(k).to eq(type: :crit, mode: :normal, child: c)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/flow_dice/plan_spec.rb`
Expected: FAIL — `uninitialized constant FlowDice::Plan`

- [ ] **Step 3: Implement the builders**

`packs/dice_engine/lib/flow_dice/plan.rb`:
```ruby
# frozen_string_literal: true

module FlowDice
  # Builder functions for plan tree nodes. Nodes are plain symbol-keyed hashes
  # so they are Opal-safe and trivially JSON-serializable.
  module Plan
    module_function

    def dice(die_kind:, faces:, count:, label:, keep: nil)
      { type: :dice, die_kind: die_kind, faces: faces, count: count, keep: keep, label: label }
    end

    def const(value)
      { type: :const, value: value }
    end

    def binary(op, left, right)
      { type: :binary, op: op, left: left, right: right }
    end

    def crit(mode, child)
      { type: :crit, mode: mode, child: child }
    end
  end
end
```

Add to `packs/dice_engine/lib/flow_dice.rb`:
```ruby
require_relative "flow_dice/plan"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/flow_dice/plan_spec.rb`
Expected: PASS — `3 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add packs/dice_engine
git commit -m "feat(engine): add Plan node builders"
```

---

## Task 4: Parser — standard dice, numbers, arithmetic

**Files:**
- Create: `packs/dice_engine/lib/flow_dice/errors.rb`
- Create: `packs/dice_engine/lib/flow_dice/parser.rb`
- Create: `packs/dice_engine/spec/flow_dice/parser_spec.rb`
- Modify: `packs/dice_engine/lib/flow_dice.rb`

Recursive-descent parser over `StringScanner`. This task establishes the skeleton (`expression`/`term`/`dice_expr`/`die_type`) for standard dice and `+`/`-` arithmetic. Dice bind tighter than arithmetic (`2d6+4` → `(2d6)+4`).

- [ ] **Step 1: Write the failing test**

`packs/dice_engine/spec/flow_dice/parser_spec.rb`:
```ruby
# frozen_string_literal: true

RSpec.describe FlowDice::Parser do
  def parse(s) = described_class.parse(s)

  it "parses an implied single die" do
    expect(parse("d20")).to eq(
      type: :dice, die_kind: :standard, faces: 20, count: 1, keep: nil, label: "d20"
    )
  end

  it "parses an explicit dice count" do
    expect(parse("3d6")).to eq(
      type: :dice, die_kind: :standard, faces: 6, count: 3, keep: nil, label: "d6"
    )
  end

  it "parses a bare number as a const" do
    expect(parse("7")).to eq(type: :const, value: 7)
  end

  it "parses dice plus a flat modifier (dice binds tighter)" do
    expect(parse("d20+5")).to eq(
      type: :binary, op: :+,
      left: { type: :dice, die_kind: :standard, faces: 20, count: 1, keep: nil, label: "d20" },
      right: { type: :const, value: 5 }
    )
  end

  it "parses a chain of terms left-associatively" do
    expect(parse("2d6+1d4-2")).to eq(
      type: :binary, op: :-,
      left: {
        type: :binary, op: :+,
        left: { type: :dice, die_kind: :standard, faces: 6, count: 2, keep: nil, label: "d6" },
        right: { type: :dice, die_kind: :standard, faces: 4, count: 1, keep: nil, label: "d4" }
      },
      right: { type: :const, value: 2 }
    )
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/flow_dice/parser_spec.rb`
Expected: FAIL — `uninitialized constant FlowDice::Parser`

- [ ] **Step 3: Implement errors and the parser skeleton**

`packs/dice_engine/lib/flow_dice/errors.rb`:
```ruby
# frozen_string_literal: true

module FlowDice
  class ParseError < StandardError; end
end
```

`packs/dice_engine/lib/flow_dice/parser.rb`:
```ruby
# frozen_string_literal: true

require "strscan"

module FlowDice
  # Recursive-descent parser: notation String -> plan tree (Plan nodes).
  # Server-side only (uses StringScanner); never compiled to Opal.
  class Parser
    def self.parse(notation)
      new(notation).parse
    end

    def initialize(notation)
      @source = notation.to_s
      @ss = StringScanner.new(@source.gsub(/\s+/, ""))
    end

    def parse
      raise ParseError, "empty notation" if @ss.eos?

      node = expression
      raise ParseError, "unexpected input: #{@ss.rest.inspect}" unless @ss.eos?

      node
    end

    private

    def expression
      node = term
      while (op = @ss.scan(/[+\-]/))
        node = Plan.binary(op == "+" ? :+ : :-, node, term)
      end
      node
    end

    def term
      if (num = @ss.scan(/\d+/))
        @ss.check(/d/) ? dice_expr(num.to_i) : Plan.const(num.to_i)
      elsif @ss.check(/d/)
        dice_expr(1)
      else
        raise ParseError, "expected a number or die at #{@ss.rest.inspect}"
      end
    end

    def dice_expr(count)
      die_type(count)
    end

    def die_type(count)
      @ss.scan(/d/) || raise(ParseError, "expected 'd'")

      if (n = @ss.scan(/\d+/))
        Plan.dice(die_kind: :standard, faces: n.to_i, count: count, label: "d#{n}")
      else
        raise ParseError, "invalid die type at #{@ss.rest.inspect}"
      end
    end
  end
end
```

Add to `packs/dice_engine/lib/flow_dice.rb` (errors before parser):
```ruby
require_relative "flow_dice/errors"
require_relative "flow_dice/parser"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/flow_dice/parser_spec.rb`
Expected: PASS — `5 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add packs/dice_engine
git commit -m "feat(engine): parse standard dice, numbers, and arithmetic"
```

---

## Task 5: Parser — keep and crit

**Files:**
- Modify: `packs/dice_engine/lib/flow_dice/parser.rb`
- Modify: `packs/dice_engine/spec/flow_dice/parser_spec.rb`

Binding order within a dice term: die → keep → crit. `kh`/`kl` default to N=1; `c`/`C` wrap the dice node.

- [ ] **Step 1: Write the failing tests**

Append inside the `RSpec.describe FlowDice::Parser` block in `parser_spec.rb`:
```ruby
  it "parses keep-highest with an implied 1" do
    expect(parse("2d20kh")[:keep]).to eq(mode: :high, n: 1)
  end

  it "parses keep-lowest with an explicit count" do
    expect(parse("4d6kl3")[:keep]).to eq(mode: :low, n: 3)
  end

  it "wraps a dice node in a normal crit" do
    expect(parse("2d6c")).to eq(
      type: :crit, mode: :normal,
      child: { type: :dice, die_kind: :standard, faces: 6, count: 2, keep: nil, label: "d6" }
    )
  end

  it "wraps a dice node in a Perkins crit" do
    expect(parse("d8C")[:mode]).to eq(:perkins)
  end

  it "keeps the flat modifier outside the crit" do
    expect(parse("d12c+5")).to eq(
      type: :binary, op: :+,
      left: {
        type: :crit, mode: :normal,
        child: { type: :dice, die_kind: :standard, faces: 12, count: 1, keep: nil, label: "d12" }
      },
      right: { type: :const, value: 5 }
    )
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/flow_dice/parser_spec.rb`
Expected: FAIL — keep is `nil`, no crit wrapping (e.g. `"2d6c"` leaves `c` as unexpected input)

- [ ] **Step 3: Extend the parser**

Replace the `dice_expr` method in `parser.rb` with:
```ruby
    def dice_expr(count)
      die = die_type(count)
      die = apply_keep(die)
      apply_crit(die)
    end

    def apply_keep(die)
      if @ss.scan(/kh/)
        die.merge(keep: { mode: :high, n: (@ss.scan(/\d+/) || "1").to_i })
      elsif @ss.scan(/kl/)
        die.merge(keep: { mode: :low, n: (@ss.scan(/\d+/) || "1").to_i })
      else
        die
      end
    end

    def apply_crit(die)
      if @ss.scan(/c/)
        Plan.crit(:normal, die)
      elsif @ss.scan(/C/)
        Plan.crit(:perkins, die)
      else
        die
      end
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/flow_dice/parser_spec.rb`
Expected: PASS — `10 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add packs/dice_engine
git commit -m "feat(engine): parse keep (kh/kl) and crit (c/C)"
```

---

## Task 6: Parser — custom faces, ranges, d%, d100

**Files:**
- Modify: `packs/dice_engine/lib/flow_dice/parser.rb`
- Modify: `packs/dice_engine/spec/flow_dice/parser_spec.rb`

`d{a,b,…}` is an explicit face set; `d[a..b]` is a range normalized to explicit faces; `d%` is the percentile pair (`die_kind: :percentile`, `faces: 100`); `d100` is a standard die with `faces: 100`.

- [ ] **Step 1: Write the failing tests**

Append inside the `parser_spec.rb` describe block:
```ruby
  it "parses an explicit custom face set" do
    expect(parse("d{1,3,5,7}")).to eq(
      type: :dice, die_kind: :custom, faces: [1, 3, 5, 7], count: 1, keep: nil, label: "d{1,3,5,7}"
    )
  end

  it "parses a custom face set with negatives" do
    expect(parse("d{-1,0,1}")[:faces]).to eq([-1, 0, 1])
  end

  it "normalizes a range to explicit faces" do
    expect(parse("d[0..5]")).to eq(
      type: :dice, die_kind: :custom, faces: [0, 1, 2, 3, 4, 5], count: 1, keep: nil, label: "d[0..5]"
    )
  end

  it "parses percentile as a distinct die kind" do
    expect(parse("d%")).to eq(
      type: :dice, die_kind: :percentile, faces: 100, count: 1, keep: nil, label: "d%"
    )
  end

  it "parses d100 as a flat standard die" do
    expect(parse("d100")).to eq(
      type: :dice, die_kind: :standard, faces: 100, count: 1, keep: nil, label: "d100"
    )
  end

  it "parses a percentile bonus die (keep applies to the pair)" do
    expect(parse("2d%kl")).to eq(
      type: :dice, die_kind: :percentile, faces: 100, count: 2,
      keep: { mode: :low, n: 1 }, label: "d%"
    )
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/flow_dice/parser_spec.rb`
Expected: FAIL — `invalid die type` for `{`, `[`, and `%`

- [ ] **Step 3: Extend `die_type`**

Replace the `die_type` method in `parser.rb` with:
```ruby
    def die_type(count)
      @ss.scan(/d/) || raise(ParseError, "expected 'd'")

      if @ss.scan(/%/)
        Plan.dice(die_kind: :percentile, faces: 100, count: count, label: "d%")
      elsif @ss.scan(/\{/)
        faces = face_set
        Plan.dice(die_kind: :custom, faces: faces, count: count, label: "d{#{faces.join(',')}}")
      elsif @ss.scan(/\[/)
        lo, hi = face_range
        Plan.dice(die_kind: :custom, faces: (lo..hi).to_a, count: count, label: "d[#{lo}..#{hi}]")
      elsif (n = @ss.scan(/\d+/))
        Plan.dice(die_kind: :standard, faces: n.to_i, count: count, label: "d#{n}")
      else
        raise ParseError, "invalid die type at #{@ss.rest.inspect}"
      end
    end

    def face_set
      values = []
      loop do
        v = @ss.scan(/-?\d+/) || raise(ParseError, "expected a face value at #{@ss.rest.inspect}")
        values << v.to_i
        break unless @ss.scan(/,/)
      end
      @ss.scan(/\}/) || raise(ParseError, "expected '}' at #{@ss.rest.inspect}")
      values
    end

    def face_range
      lo = @ss.scan(/-?\d+/) || raise(ParseError, "expected range start at #{@ss.rest.inspect}")
      @ss.scan(/\.\./) || raise(ParseError, "expected '..' at #{@ss.rest.inspect}")
      hi = @ss.scan(/-?\d+/) || raise(ParseError, "expected range end at #{@ss.rest.inspect}")
      @ss.scan(/\]/) || raise(ParseError, "expected ']' at #{@ss.rest.inspect}")
      lo = lo.to_i
      hi = hi.to_i
      raise ParseError, "range start #{lo} > end #{hi}" if lo > hi

      [lo, hi]
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/flow_dice/parser_spec.rb`
Expected: PASS — `16 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add packs/dice_engine
git commit -m "feat(engine): parse custom faces, ranges, d% and d100"
```

---

## Task 7: Parser — errors and whitespace

**Files:**
- Modify: `packs/dice_engine/spec/flow_dice/parser_spec.rb`

The parser already raises `ParseError` and strips whitespace; this task locks that behavior with tests. No implementation change is expected — if a test fails, fix the parser to satisfy it.

- [ ] **Step 1: Write the failing/locking tests**

Append inside the `parser_spec.rb` describe block:
```ruby
  it "ignores surrounding and internal whitespace" do
    expect(parse("  2d6 + 3 ")).to eq(parse("2d6+3"))
  end

  it "raises on empty notation" do
    expect { parse("") }.to raise_error(FlowDice::ParseError, /empty/)
  end

  it "raises on trailing garbage" do
    expect { parse("2d6 xyz") }.to raise_error(FlowDice::ParseError, /unexpected/)
  end

  it "raises on a bare 'd' with no die type" do
    expect { parse("d") }.to raise_error(FlowDice::ParseError)
  end

  it "raises on an unterminated face set" do
    expect { parse("d{1,2") }.to raise_error(FlowDice::ParseError)
  end

  it "raises on an inverted range" do
    expect { parse("d[5..0]") }.to raise_error(FlowDice::ParseError, /start/)
  end
```

- [ ] **Step 2: Run tests**

Run: `bundle exec rspec spec/flow_dice/parser_spec.rb`
Expected: PASS — `22 examples, 0 failures` (if any fail, adjust the parser to satisfy the contract, then re-run)

- [ ] **Step 3: Commit**

```bash
git add packs/dice_engine
git commit -m "test(engine): lock parser error handling and whitespace"
```

---

## Task 8: Evaluator — Result, const, binary, standard dice

**Files:**
- Create: `packs/dice_engine/lib/flow_dice/evaluator.rb`
- Create: `packs/dice_engine/spec/flow_dice/evaluator_spec.rb`
- Modify: `packs/dice_engine/lib/flow_dice.rb`

The evaluator walks a plan against an RNG and returns a `Result`. It takes a `ParseResult` (for the `notation`), but tests construct one inline. Written in plain Opal-safe Ruby.

- [ ] **Step 1: Write the failing test**

`packs/dice_engine/spec/flow_dice/evaluator_spec.rb`:
```ruby
# frozen_string_literal: true

RSpec.describe FlowDice::Evaluator do
  ParseResult = FlowDice::ParseResult

  def evaluate(plan, notation, rng_values)
    rng = FlowDice::SequenceRng.new(rng_values)
    described_class.evaluate(ParseResult.new(notation, plan, nil), rng: rng)
  end

  it "evaluates a constant" do
    result = evaluate(FlowDice::Plan.const(5), "5", [])
    expect(result.kind).to eq(:sum)
    expect(result.total).to eq(5)
    expect(result.notation).to eq("5")
    expect(result.dice).to eq([])
  end

  it "evaluates addition and subtraction" do
    plan = FlowDice::Plan.binary(:-,
      FlowDice::Plan.binary(:+, FlowDice::Plan.const(10), FlowDice::Plan.const(4)),
      FlowDice::Plan.const(3))
    expect(evaluate(plan, "10+4-3", []).total).to eq(11)
  end

  it "rolls standard dice and records each die" do
    plan = FlowDice::Plan.dice(die_kind: :standard, faces: 6, count: 3, label: "d6")
    result = evaluate(plan, "3d6", [3, 5, 2])
    expect(result.total).to eq(10)
    expect(result.dice).to eq([
      { die: "d6", value: 3, kept: true },
      { die: "d6", value: 5, kept: true },
      { die: "d6", value: 2, kept: true }
    ])
  end

  it "adds a flat modifier to a dice roll" do
    plan = FlowDice::Plan.binary(:+,
      FlowDice::Plan.dice(die_kind: :standard, faces: 20, count: 1, label: "d20"),
      FlowDice::Plan.const(5))
    expect(evaluate(plan, "d20+5", [18]).total).to eq(23)
  end

  it "produces a non-empty breakdown string" do
    plan = FlowDice::Plan.dice(die_kind: :standard, faces: 6, count: 2, label: "d6")
    expect(evaluate(plan, "2d6", [4, 2]).breakdown).to be_a(String).and be_present_string
  end
end

RSpec::Matchers.define :be_present_string do
  match { |s| s.is_a?(String) && !s.strip.empty? }
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/flow_dice/evaluator_spec.rb`
Expected: FAIL — `uninitialized constant FlowDice::Evaluator` (and `FlowDice::ParseResult`)

- [ ] **Step 3: Implement the evaluator (const/binary/standard dice)**

`packs/dice_engine/lib/flow_dice/evaluator.rb`:
```ruby
# frozen_string_literal: true

module FlowDice
  ParseResult = Struct.new(:notation, :plan, :explanation) unless defined?(ParseResult)
  Result = Struct.new(:kind, :total, :notation, :dice, :breakdown) unless defined?(Result)

  # Walks a plan tree against an injected RNG. Plain Opal-safe Ruby — this file
  # is compiled to JS via Opal in increment #3.
  module Evaluator
    module_function

    def evaluate(parsed, rng: SecureRandomRng.new)
      dice = []
      total = eval_node(parsed.plan, rng, dice)
      Result.new(:sum, total, parsed.notation, dice, build_breakdown(dice, total))
    end

    def eval_node(node, rng, dice)
      case node[:type]
      when :const  then node[:value]
      when :binary then eval_binary(node, rng, dice)
      when :dice   then eval_dice(node, rng, dice)
      else raise ArgumentError, "unknown node type: #{node[:type].inspect}"
      end
    end

    def eval_binary(node, rng, dice)
      left = eval_node(node[:left], rng, dice)
      right = eval_node(node[:right], rng, dice)
      node[:op] == :+ ? left + right : left - right
    end

    def eval_dice(node, rng, dice)
      rolls = Array.new(node[:count]) { roll_one(node[:faces], rng) }
      rolls.each { |v| dice << { die: node[:label], value: v, kept: true } }
      rolls.sum
    end

    def roll_one(faces, rng)
      faces.is_a?(Array) ? faces[rng.int(0, faces.length - 1)] : rng.int(1, faces)
    end

    def build_breakdown(dice, total)
      return total.to_s if dice.empty?

      parts = dice.map { |d| d[:kept] ? d[:value].to_s : "#{d[:value]} (dropped)" }
      "#{parts.join(', ')} = #{total}"
    end
  end
end
```

Add to `packs/dice_engine/lib/flow_dice.rb`:
```ruby
require_relative "flow_dice/evaluator"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/flow_dice/evaluator_spec.rb`
Expected: PASS — `5 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add packs/dice_engine
git commit -m "feat(engine): evaluate const, binary, and standard dice"
```

---

## Task 9: Evaluator — keep highest/lowest

**Files:**
- Modify: `packs/dice_engine/lib/flow_dice/evaluator.rb`
- Modify: `packs/dice_engine/spec/flow_dice/evaluator_spec.rb`

Keep marks which dice contribute. Kept dice sum into the total; dropped dice are still recorded with `kept: false`.

- [ ] **Step 1: Write the failing tests**

Append inside the `RSpec.describe FlowDice::Evaluator` block:
```ruby
  it "keeps the highest die (advantage)" do
    plan = FlowDice::Plan.dice(die_kind: :standard, faces: 20, count: 2, label: "d20",
                               keep: { mode: :high, n: 1 })
    result = evaluate(plan, "2d20kh", [18, 7])
    expect(result.total).to eq(18)
    expect(result.dice).to eq([
      { die: "d20", value: 18, kept: true },
      { die: "d20", value: 7, kept: false }
    ])
  end

  it "keeps the lowest die (disadvantage)" do
    plan = FlowDice::Plan.dice(die_kind: :standard, faces: 20, count: 2, label: "d20",
                               keep: { mode: :low, n: 1 })
    expect(evaluate(plan, "2d20kl", [18, 7]).total).to eq(7)
  end

  it "keeps the highest 3 of 4 (ability scores)" do
    plan = FlowDice::Plan.dice(die_kind: :standard, faces: 6, count: 4, label: "d6",
                               keep: { mode: :high, n: 3 })
    result = evaluate(plan, "4d6kh3", [6, 1, 4, 3])
    expect(result.total).to eq(13)
    expect(result.dice.select { |d| d[:kept] }.map { |d| d[:value] }).to contain_exactly(6, 4, 3)
    expect(result.dice.reject { |d| d[:kept] }.map { |d| d[:value] }).to eq([1])
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/flow_dice/evaluator_spec.rb`
Expected: FAIL — all dice still marked `kept: true`, total sums everything

- [ ] **Step 3: Add keep handling**

Replace `eval_dice` in `evaluator.rb` with:
```ruby
    def eval_dice(node, rng, dice)
      rolls = Array.new(node[:count]) { roll_one(node[:faces], rng) }
      kept = keep_flags(rolls, node[:keep])
      rolls.each_with_index { |v, i| dice << { die: node[:label], value: v, kept: kept[i] } }
      rolls.each_index.select { |i| kept[i] }.sum { |i| rolls[i] }
    end

    # Returns an array of booleans (one per roll) marking which dice are kept.
    def keep_flags(rolls, keep)
      return Array.new(rolls.length, true) if keep.nil?

      order = (0...rolls.length).sort_by { |i| rolls[i] } # ascending by value
      selected = keep[:mode] == :high ? order.last(keep[:n]) : order.first(keep[:n])
      Array.new(rolls.length) { |i| selected.include?(i) }
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/flow_dice/evaluator_spec.rb`
Expected: PASS — `8 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add packs/dice_engine
git commit -m "feat(engine): evaluate keep highest/lowest"
```

---

## Task 10: Evaluator — crit (normal and Perkins)

**Files:**
- Modify: `packs/dice_engine/lib/flow_dice/evaluator.rb`
- Modify: `packs/dice_engine/spec/flow_dice/evaluator_spec.rb`

Normal crit (`c`) doubles the child dice count, then evaluates. Perkins crit (`C`) adds the maximum of one set (`count × max_face`) and rolls the child once more. Static modifiers stay outside (handled by tree position). Crit always wraps a dice node.

- [ ] **Step 1: Write the failing tests**

Append inside the `RSpec.describe FlowDice::Evaluator` block:
```ruby
  it "doubles the dice on a normal crit" do
    plan = FlowDice::Plan.crit(:normal,
      FlowDice::Plan.dice(die_kind: :standard, faces: 6, count: 2, label: "d6"))
    result = evaluate(plan, "2d6c", [3, 5, 2, 6]) # rolls 4d6
    expect(result.total).to eq(16)
    expect(result.dice.length).to eq(4)
  end

  it "maxes one set and rolls again on a Perkins crit" do
    plan = FlowDice::Plan.crit(:perkins,
      FlowDice::Plan.dice(die_kind: :standard, faces: 6, count: 2, label: "d6"))
    result = evaluate(plan, "2d6C", [3, 4]) # 12 (max of 2d6) + (3+4)
    expect(result.total).to eq(19)
    expect(result.dice.map { |d| d[:value] }).to eq([3, 4])
  end

  it "keeps the flat modifier outside a Perkins crit" do
    plan = FlowDice::Plan.binary(:+,
      FlowDice::Plan.crit(:perkins,
        FlowDice::Plan.dice(die_kind: :standard, faces: 12, count: 1, label: "d12")),
      FlowDice::Plan.const(5))
    # 12 (max d12) + 7 (rolled) + 5
    expect(evaluate(plan, "d12C+5", [7]).total).to eq(24)
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/flow_dice/evaluator_spec.rb`
Expected: FAIL — `unknown node type: :crit`

- [ ] **Step 3: Add crit handling**

Add `:crit` to the `eval_node` case in `evaluator.rb`:
```ruby
      when :crit   then eval_crit(node, rng, dice)
```

Then add these methods to the `Evaluator` module:
```ruby
    def eval_crit(node, rng, dice)
      child = node[:child]
      case node[:mode]
      when :normal
        eval_dice(child.merge(count: child[:count] * 2), rng, dice)
      when :perkins
        max_set = child[:count] * max_face(child[:faces])
        max_set + eval_dice(child, rng, dice)
      else
        raise ArgumentError, "unknown crit mode: #{node[:mode].inspect}"
      end
    end

    def max_face(faces)
      faces.is_a?(Array) ? faces.max : faces
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/flow_dice/evaluator_spec.rb`
Expected: PASS — `11 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add packs/dice_engine
git commit -m "feat(engine): evaluate normal and Perkins crits"
```

---

## Task 11: Evaluator — custom faces

**Files:**
- Modify: `packs/dice_engine/spec/flow_dice/evaluator_spec.rb`

Custom-face dice are already handled by `roll_one` (Array branch picks `faces[index]`). This task locks the behavior — including the Custom Skill System base die — with tests. The RNG sequence supplies **indices** into the face array, not face values.

- [ ] **Step 1: Write the failing/locking tests**

Append inside the `RSpec.describe FlowDice::Evaluator` block:
```ruby
  it "rolls an explicit custom face set by index" do
    plan = FlowDice::Plan.dice(die_kind: :custom, faces: [1, 3, 5, 7], count: 1, label: "d{1,3,5,7}")
    # index 2 -> face 5
    result = evaluate(plan, "d{1,3,5,7}", [2])
    expect(result.total).to eq(5)
    expect(result.dice).to eq([{ die: "d{1,3,5,7}", value: 5, kept: true }])
  end

  it "rolls the Custom Skill System base die (4d[0..5])" do
    plan = FlowDice::Plan.dice(die_kind: :custom, faces: (0..5).to_a, count: 4, label: "d[0..5]")
    # indices 5,0,3,2 -> faces 5,0,3,2
    expect(evaluate(plan, "4d[0..5]", [5, 0, 3, 2]).total).to eq(10)
  end

  it "applies keep to a custom-face skill roll (6d[0..5]kh4)" do
    plan = FlowDice::Plan.dice(die_kind: :custom, faces: (0..5).to_a, count: 6, label: "d[0..5]",
                               keep: { mode: :high, n: 4 })
    # indices -> faces 5,4,1,0,3,2 ; keep highest 4 -> 5+4+3+2 = 14
    result = evaluate(plan, "6d[0..5]kh4", [5, 4, 1, 0, 3, 2])
    expect(result.total).to eq(14)
    expect(result.dice.reject { |d| d[:kept] }.map { |d| d[:value] }).to contain_exactly(1, 0)
  end
```

- [ ] **Step 2: Run tests**

Run: `bundle exec rspec spec/flow_dice/evaluator_spec.rb`
Expected: PASS — `14 examples, 0 failures` (no implementation change expected; fix `roll_one`/`keep_flags` if any fail)

- [ ] **Step 3: Commit**

```bash
git add packs/dice_engine
git commit -m "test(engine): lock custom-face and Custom Skill System evaluation"
```

---

## Task 12: Evaluator — percentile pair (d%)

**Files:**
- Modify: `packs/dice_engine/lib/flow_dice/evaluator.rb`
- Modify: `packs/dice_engine/spec/flow_dice/evaluator_spec.rb`

`d%` rolls `count` tens dice (each 0–9, shown as 0,10,…,90) and one units die (0–9). Keep selects exactly one tens die (`kl` = bonus die, `kh` = penalty die); the units die is fixed. The 00+0 result is **100**. RNG call order: `count` tens draws (each `int(0,9)`), then one units draw (`int(0,9)`).

- [ ] **Step 1: Write the failing tests**

Append inside the `RSpec.describe FlowDice::Evaluator` block:
```ruby
  it "rolls a standard percentile pair" do
    plan = FlowDice::Plan.dice(die_kind: :percentile, faces: 100, count: 1, label: "d%")
    result = evaluate(plan, "d%", [7, 3]) # tens 70, units 3
    expect(result.total).to eq(73)
    expect(result.dice).to eq([
      { die: "d%(tens)", value: 70, kept: true },
      { die: "d%(units)", value: 3, kept: true }
    ])
  end

  it "applies the 00+0 = 100 rule" do
    plan = FlowDice::Plan.dice(die_kind: :percentile, faces: 100, count: 1, label: "d%")
    expect(evaluate(plan, "d%", [0, 0]).total).to eq(100)
  end

  it "keeps the lowest tens on a CoC bonus die (2d%kl)" do
    plan = FlowDice::Plan.dice(die_kind: :percentile, faces: 100, count: 2, label: "d%",
                               keep: { mode: :low, n: 1 })
    # tens 70, 40 ; units 3 ; keep low tens -> 40 ; 40 + 3 = 43
    result = evaluate(plan, "2d%kl", [7, 4, 3])
    expect(result.total).to eq(43)
    expect(result.dice).to eq([
      { die: "d%(tens)", value: 70, kept: false },
      { die: "d%(tens)", value: 40, kept: true },
      { die: "d%(units)", value: 3, kept: true }
    ])
  end

  it "keeps the highest tens on a CoC penalty die (2d%kh)" do
    plan = FlowDice::Plan.dice(die_kind: :percentile, faces: 100, count: 2, label: "d%",
                               keep: { mode: :high, n: 1 })
    # tens 70, 40 ; units 3 ; keep high tens -> 70 ; 73
    expect(evaluate(plan, "2d%kh", [7, 4, 3]).total).to eq(73)
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/flow_dice/evaluator_spec.rb`
Expected: FAIL — percentile is rolled as a single numeric die (wrong values; no tens/units records)

- [ ] **Step 3: Add percentile handling**

In `evaluator.rb`, change `eval_dice` to dispatch on `die_kind`. Replace the first line of `eval_dice`'s body by wrapping it:
```ruby
    def eval_dice(node, rng, dice)
      return eval_percentile(node, rng, dice) if node[:die_kind] == :percentile

      rolls = Array.new(node[:count]) { roll_one(node[:faces], rng) }
      kept = keep_flags(rolls, node[:keep])
      rolls.each_with_index { |v, i| dice << { die: node[:label], value: v, kept: kept[i] } }
      rolls.each_index.select { |i| kept[i] }.sum { |i| rolls[i] }
    end

    def eval_percentile(node, rng, dice)
      tens = Array.new(node[:count]) { rng.int(0, 9) * 10 }
      units = rng.int(0, 9)
      keep = node[:keep] || { mode: :high, n: 1 } # count == 1 selects the only tens
      order = (0...tens.length).sort_by { |i| tens[i] }
      kept_index = keep[:mode] == :high ? order.last : order.first

      tens.each_with_index do |t, i|
        dice << { die: "d%(tens)", value: t, kept: i == kept_index }
      end
      dice << { die: "d%(units)", value: units, kept: true }

      value = tens[kept_index] + units
      value.zero? ? 100 : value
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/flow_dice/evaluator_spec.rb`
Expected: PASS — `18 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add packs/dice_engine
git commit -m "feat(engine): evaluate percentile pairs with bonus/penalty dice"
```

---

## Task 13: Explanation generator

**Files:**
- Create: `packs/dice_engine/lib/flow_dice/explanation.rb`
- Create: `packs/dice_engine/spec/flow_dice/explanation_spec.rb`
- Modify: `packs/dice_engine/lib/flow_dice.rb`

Generates plain-English text from a plan tree. Server-side only (not Opal-compiled). Note the en-dash (`–`) in range output.

- [ ] **Step 1: Write the failing test**

`packs/dice_engine/spec/flow_dice/explanation_spec.rb`:
```ruby
# frozen_string_literal: true

RSpec.describe FlowDice::Explanation do
  def explain(notation) = described_class.generate(FlowDice::Parser.parse(notation))

  it "explains dice with keep and a modifier" do
    expect(explain("2d20kh+5")).to eq("Roll 2d20, keep the highest, add 5")
  end

  it "explains keep-highest-N" do
    expect(explain("4d6kh3")).to eq("Roll 4d6, keep the highest 3")
  end

  it "explains a range die with keep" do
    expect(explain("6d[0..5]kh4")).to eq("Roll 6 dice (0–5), keep the highest 4")
  end

  it "explains a single die" do
    expect(explain("d20")).to eq("Roll d20")
  end

  it "explains a Perkins crit" do
    expect(explain("2d6C")).to eq("Roll 2d6 (Perkins crit)")
  end

  it "explains a percentile bonus die" do
    expect(explain("2d%kl")).to eq("Roll percentile with 1 bonus die")
  end

  it "explains a percentile penalty die (plural)" do
    expect(explain("3d%kh")).to eq("Roll percentile with 2 penalty dice")
  end

  it "explains subtraction" do
    expect(explain("d20-2")).to eq("Roll d20, subtract 2")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/flow_dice/explanation_spec.rb`
Expected: FAIL — `uninitialized constant FlowDice::Explanation`

- [ ] **Step 3: Implement the generator**

`packs/dice_engine/lib/flow_dice/explanation.rb`:
```ruby
# frozen_string_literal: true

module FlowDice
  # Plan tree -> plain-English explanation. Server-side only.
  module Explanation
    module_function

    def generate(node)
      text = render(node)
      text.sub(/\A./, &:upcase)
    end

    def render(node)
      case node[:type]
      when :const  then node[:value].to_s
      when :binary then render_binary(node)
      when :crit   then "#{render(node[:child])} (#{node[:mode] == :perkins ? 'Perkins' : 'normal'} crit)"
      when :dice   then render_dice(node)
      else raise ArgumentError, "unknown node type: #{node[:type].inspect}"
      end
    end

    def render_binary(node)
      left = render(node[:left])
      right = node[:right]
      if right[:type] == :const
        verb = node[:op] == :+ ? "add" : "subtract"
        "#{left}, #{verb} #{right[:value]}"
      else
        conj = node[:op] == :+ ? "plus" : "minus"
        "#{left}, #{conj} #{render(right)}"
      end
    end

    def render_dice(node)
      phrase = "roll #{dice_phrase(node)}"
      phrase += keep_phrase(node[:keep]) if node[:keep] && node[:die_kind] != :percentile
      phrase
    end

    def dice_phrase(node)
      case node[:die_kind]
      when :percentile
        node[:count] > 1 ? "percentile#{percentile_keep_phrase(node)}" : "percentile"
      when :custom
        if (m = node[:label].match(/\Ad\[(-?\d+)\.\.(-?\d+)\]\z/))
          "#{node[:count]} #{node[:count] == 1 ? 'die' : 'dice'} (#{m[1]}–#{m[2]})"
        else
          "#{count_prefix(node[:count])}#{node[:label]}"
        end
      else
        "#{count_prefix(node[:count])}d#{node[:faces]}"
      end
    end

    def count_prefix(count)
      count == 1 ? "" : count.to_s
    end

    def keep_phrase(keep)
      which = keep[:mode] == :high ? "highest" : "lowest"
      keep[:n] == 1 ? ", keep the #{which}" : ", keep the #{which} #{keep[:n]}"
    end

    def percentile_keep_phrase(node)
      extra = node[:count] - 1
      kind = node[:keep] && node[:keep][:mode] == :high ? "penalty" : "bonus"
      " with #{extra} #{kind} #{extra == 1 ? 'die' : 'dice'}"
    end
  end
end
```

Add to `packs/dice_engine/lib/flow_dice.rb`:
```ruby
require_relative "flow_dice/explanation"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/flow_dice/explanation_spec.rb`
Expected: PASS — `8 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add packs/dice_engine
git commit -m "feat(engine): add plain-English explanation generator"
```

---

## Task 14: Engine façade

**Files:**
- Create: `packs/dice_engine/lib/flow_dice/engine.rb`
- Create: `packs/dice_engine/spec/flow_dice/engine_spec.rb`
- Modify: `packs/dice_engine/lib/flow_dice.rb`

The public API. `parse` returns a `ParseResult` (notation + plan + explanation); `evaluate` runs it; `explain` returns the text; `roll` is parse-then-evaluate.

- [ ] **Step 1: Write the failing test**

`packs/dice_engine/spec/flow_dice/engine_spec.rb`:
```ruby
# frozen_string_literal: true

RSpec.describe FlowDice::Engine do
  it "parses notation into a ParseResult" do
    parsed = described_class.parse("2d20kh+5")
    expect(parsed.notation).to eq("2d20kh+5")
    expect(parsed.plan[:type]).to eq(:binary)
    expect(parsed.explanation).to eq("Roll 2d20, keep the highest, add 5")
  end

  it "evaluates a ParseResult against an injected RNG" do
    parsed = described_class.parse("2d20kh+5")
    result = described_class.evaluate(parsed, rng: FlowDice::SequenceRng.new([18, 7]))
    expect(result.total).to eq(23)
  end

  it "rolls notation end-to-end with an injected RNG" do
    result = described_class.roll("3d6", rng: FlowDice::SequenceRng.new([3, 5, 2]))
    expect(result.total).to eq(10)
    expect(result.notation).to eq("3d6")
  end

  it "explains notation directly" do
    expect(described_class.explain("d20-2")).to eq("Roll d20, subtract 2")
  end

  it "rolls with the default secure RNG within range" do
    result = described_class.roll("d20")
    expect(result.total).to be_between(1, 20)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/flow_dice/engine_spec.rb`
Expected: FAIL — `uninitialized constant FlowDice::Engine`

- [ ] **Step 3: Implement the façade**

`packs/dice_engine/lib/flow_dice/engine.rb`:
```ruby
# frozen_string_literal: true

module FlowDice
  # Public API for the dice engine.
  module Engine
    module_function

    def parse(notation)
      plan = Parser.parse(notation)
      ParseResult.new(notation, plan, Explanation.generate(plan))
    end

    def evaluate(parsed, rng: SecureRandomRng.new)
      Evaluator.evaluate(parsed, rng: rng)
    end

    def explain(notation)
      parse(notation).explanation
    end

    def roll(notation, rng: SecureRandomRng.new)
      evaluate(parse(notation), rng: rng)
    end
  end
end
```

Add to `packs/dice_engine/lib/flow_dice.rb` (last require):
```ruby
require_relative "flow_dice/engine"
```

- [ ] **Step 4: Run the full suite to verify everything passes**

Run: `bundle exec rspec`
Expected: PASS — all specs green

- [ ] **Step 5: Commit**

```bash
git add packs/dice_engine
git commit -m "feat(engine): add public Engine façade (parse/evaluate/explain/roll)"
```

---

## Task 15: Golden fixtures (parity-ready, incl. Custom Skill System)

**Files:**
- Create: `packs/dice_engine/spec/fixtures/golden_rolls.rb`
- Create: `packs/dice_engine/spec/flow_dice/fixtures_spec.rb`

A single data table of `{notation, rng, expected}` cases driving the full parse→evaluate path. This is the contract increment #3 reuses to verify the Opal-compiled JS evaluator produces identical results from the identical RNG sequence.

- [ ] **Step 1: Create the fixtures data**

`packs/dice_engine/spec/fixtures/golden_rolls.rb`:
```ruby
# frozen_string_literal: true

# Each case: notation, the exact RNG draw sequence, and the expected total + kept values.
# RNG draws are in evaluator call order (see per-mechanic specs for ordering rules).
FlowDice::GOLDEN_ROLLS = [
  { notation: "d20",          rng: [14],            total: 14,  kept: [14] },
  { notation: "3d6+2",        rng: [3, 5, 2],       total: 12,  kept: [3, 5, 2] },
  { notation: "2d20kh+5",     rng: [18, 7],         total: 23,  kept: [18] },
  { notation: "2d20kl",       rng: [18, 7],         total: 7,   kept: [7] },
  { notation: "4d6kh3",       rng: [6, 1, 4, 3],    total: 13,  kept: [6, 4, 3] },
  { notation: "2d6c",         rng: [3, 5, 2, 6],    total: 16,  kept: [3, 5, 2, 6] },
  { notation: "2d6C",         rng: [3, 4],          total: 19,  kept: [3, 4] },
  { notation: "d100",         rng: [73],            total: 73,  kept: [73] },
  { notation: "d%",           rng: [7, 3],          total: 73,  kept: [70, 3] },
  { notation: "d%",           rng: [0, 0],          total: 100, kept: [0, 0] },
  { notation: "2d%kl",        rng: [7, 4, 3],       total: 43,  kept: [40, 3] },
  # Custom Skill System (Chris's homebrew) — must stay green.
  { notation: "4d[0..5]",     rng: [5, 0, 3, 2],    total: 10,  kept: [5, 0, 3, 2] },
  { notation: "6d[0..5]kh4",  rng: [5, 4, 1, 0, 3, 2], total: 14, kept: [5, 4, 3, 2] }
].freeze
```

- [ ] **Step 2: Write the fixtures spec**

`packs/dice_engine/spec/flow_dice/fixtures_spec.rb`:
```ruby
# frozen_string_literal: true

require_relative "../fixtures/golden_rolls"

RSpec.describe "golden rolls" do
  FlowDice::GOLDEN_ROLLS.each do |c|
    it "#{c[:notation]} with rng #{c[:rng].inspect} totals #{c[:total]}" do
      result = FlowDice::Engine.roll(c[:notation], rng: FlowDice::SequenceRng.new(c[:rng]))
      expect(result.total).to eq(c[:total])
      expect(result.dice.select { |d| d[:kept] }.map { |d| d[:value] }).to eq(c[:kept])
    end
  end
end
```

- [ ] **Step 3: Run the fixtures**

Run: `bundle exec rspec spec/flow_dice/fixtures_spec.rb`
Expected: PASS — `13 examples, 0 failures`

- [ ] **Step 4: Run the whole suite**

Run: `bundle exec rspec`
Expected: PASS — all specs green

- [ ] **Step 5: Commit**

```bash
git add packs/dice_engine
git commit -m "test(engine): add golden-roll fixtures (incl. Custom Skill System)"
```

---

## Self-Review

**Spec coverage** (against the design doc's increment #1 scope):

| Requirement | Task |
|---|---|
| Standard dice `NdX`/`dX` | 4, 8 |
| Custom faces `d{…}` | 6, 11 |
| Ranges `d[a..b]` (normalized) | 6, 11 |
| Percentile `d%` + 00+0=100 + keep-on-tens | 6, 12 |
| Flat `d100` (distinct from `d%`) | 6, 12 (via standard path) |
| Keep `kh`/`kl` (default 1) | 5, 9 |
| Normal crit `c` (double dice) | 5, 10 |
| Perkins crit `C` (max set + reroll) | 5, 10 |
| Flat modifiers `+N`/`-N`, modifier outside crit | 4, 8, 10 |
| Secure RNG (injected; `SecureRandom`) | 2, 14 |
| Plan = typed tree (hashes), `kind` discriminator on result | 3, 8 |
| Crit as evaluator node (not pre-resolved) | 5, 10 |
| Explanation generator | 13 |
| Golden fixtures incl. Custom Skill System | 11, 15 |
| Parity-ready fixtures (RNG-sequence form) for increment #3 | 15 |

**Out-of-scope confirmed deferred:** Flows, conditionals, triggers, named params, reroll, exploding, success counting, parenthesized grouping — none appear in tasks; reserved-symbol handling is increment #2+ parser work.

**Placeholder scan:** none — every code step contains complete implementation and test code.

**Type consistency:** `Plan.dice` signature (`die_kind:, faces:, count:, label:, keep:`) is identical in Tasks 3–12; `Result`/`ParseResult` field order matches the File Structure header; `rng.int(min, max)` is used uniformly; `keep` is always `{ mode:, n: }`; dice records are always `{ die:, value:, kept: }`.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-13-dice-engine.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
