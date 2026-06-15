# Calculator UI + Roll Pipeline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. The visible-UI tasks (4–7) are frontend work — apply the **frontend-design** skill's quality bar; the approved design system is in `Section A` of the spec and project memory.

**Goal:** A mobile-first calculator at `/` that builds dice notation by tapping, rolls client-side via the Opal evaluator, and shows the result — FlowDice's first usable UI.

**Architecture:** The compiled Opal evaluator (#3) is built by a rake task into `vendor/javascript/` and served via importmap (sets `window.FlowDice`). A dependency-free `roll_pipeline.js` caches plans in IndexedDB (keyed by notation), fetches `POST /parse` on a miss, and rolls via `FlowDice.evaluate` with a `crypto`-backed RNG. A Stimulus `calculator_controller` builds the notation from taps and renders the result bottom-sheet. Tested end-to-end in a real headless browser (Capybara + cuprite).

**Tech Stack:** Rails 8 / importmap / Propshaft / Stimulus, plain CSS, Opal (build-time), Capybara + cuprite (ferrum/CDP, no Selenium). No Node.

**Working directory:** repo root (a worktree at execution time). `bundle exec rspec`.

> **Approved visual design** (signed off 2026-06-14, in project memory + the spec's Section A): dark bg `#0b0c10`, surfaces `#13141b`, accent `#8b5cff`; warm→cool color-coded dice (d4 `#ff5d5d`, d6 `#ff8a3d`, d8 `#f5b833`, d10 `#b6e34d`, d12 `#34d39b`, d20 `#38bdf8`, d100 `#8b9bff`, d% `#f472d0`, dN slate `#8a90a6`); `ui-monospace` tabular; 12–18px radii; lean tap-to-increment input; result bottom-sheet (kept = ringed, dropped = struck + dimmed).

---

## File Structure

```
lib/tasks/opal.rake                              # rake opal:build (Task 2)
vendor/javascript/flow_dice_evaluator.js         # committed Opal artifact (Task 2)
config/importmap.rb                              # pins (Tasks 2,3)
app/javascript/application.js                    # import the evaluator (Task 2)
app/javascript/roll_pipeline.js                  # IndexedDB cache + /parse + crypto RNG + evaluate (Task 3)
app/javascript/controllers/calculator_controller.js  # tap-to-build + roll + render (Tasks 5,6,7)
app/controllers/home_controller.rb               # unchanged (renders calculator)
app/views/home/index.html.erb                    # calculator markup (Task 4)
app/assets/stylesheets/calculator.css            # plain CSS, approved design (Task 4)
spec/support/capybara.rb                         # cuprite driver (Task 1)
spec/system/*.rb                                 # system specs (Tasks 1,2,4,5,6,7)
spec/flow_dice/opal_artifact_spec.rb             # freshness check (Task 2)
Gemfile                                          # + capybara, cuprite (Task 1)
```

**Pipeline API (stable across tasks):** `roll_pipeline.js` exports
`rollNotation(notation) -> Promise<{ result, explanation }>` where `result` is the
parsed `FlowDice.evaluate` object `{kind,total,notation,dice:[{die,value,kept}],breakdown}`.

---

## Task 1: Headless-browser test toolchain (de-risking gate)

System specs need real Chrome. Prove the toolchain before building anything that depends on it.

**Files:** Modify `Gemfile`; Create `spec/support/capybara.rb`, `spec/system/smoke_spec.rb`.

- [ ] **Step 1: Add the gems.** In `Gemfile` `group :test` (create it if absent):
```ruby
group :test do
  gem "capybara"
  gem "cuprite"
end
```
Run: `bundle install`. (cuprite drives headless Chrome over CDP via ferrum — no Selenium server, no chromedriver. It needs a Chrome/Chromium binary on the machine.)

- [ ] **Step 2: Configure the driver** `spec/support/capybara.rb`:
```ruby
# frozen_string_literal: true

require "capybara/cuprite"

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(app, window_size: [400, 900], headless: true)
end
Capybara.default_max_wait_time = 5

RSpec.configure do |config|
  config.before(:each, type: :system) { driven_by :cuprite }
end
```
(`spec/rails_helper.rb` already requires `spec/support/**/*.rb` from increment #2.)

- [ ] **Step 3: Write the smoke system spec** `spec/system/smoke_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "smoke", type: :system do
  it "loads the home page in a real browser" do
    visit "/"
    expect(page).to have_content("FlowDice")
  end
end
```

- [ ] **Step 4: Run it.** `bundle exec rspec spec/system/smoke_spec.rb` → expect `1 example, 0 failures`.
If cuprite cannot find/launch Chrome (e.g. "Could not find an executable for the browser"), set `browser_path:` in the driver options to the Chrome binary if one exists, or report **BLOCKED**: headless Chrome is unavailable in this environment — do not work around it; escalate so we can pick another test approach.

- [ ] **Step 5: Commit.**
```bash
git add -A && git commit -m "test(system): add Capybara + cuprite headless-browser harness"
```

---

## Task 2: Build & serve the Opal evaluator

**Files:** Create `lib/tasks/opal.rake`, `vendor/javascript/flow_dice_evaluator.js`, `spec/flow_dice/opal_artifact_spec.rb`, `spec/system/evaluator_loaded_spec.rb`; Modify `config/importmap.rb`, `app/javascript/application.js`.

- [ ] **Step 1: Write the build task** `lib/tasks/opal.rake`:
```ruby
# frozen_string_literal: true

namespace :opal do
  desc "Compile the FlowDice evaluator to vendor/javascript/flow_dice_evaluator.js"
  task build: :environment do
    js = FlowDiceOpal.build
    path = Rails.root.join("vendor/javascript/flow_dice_evaluator.js")
    File.write(path, js)
    puts "wrote #{path} (#{js.bytesize} bytes)"
  end
end
```
And a shared builder so the rake task and the freshness spec agree — `lib/flow_dice_opal.rb`:
```ruby
# frozen_string_literal: true

require "opal"

# Compiles the Opal evaluator entry (runtime + entry) to a JS string. Single
# source of truth for both `rake opal:build` and the freshness spec.
module FlowDiceOpal
  def self.build
    Opal.append_path(Rails.root.join("packs/dice_engine/lib").to_s)
    builder = Opal::Builder.new
    builder.build("opal")
    builder.build("flow_dice/opal/entry")
    builder.to_s
  end
end
```
Require it from the rake task (add at top of `opal.rake`): `require_relative "../flow_dice_opal"`.

- [ ] **Step 2: Generate the artifact.** Run: `bundle exec rake opal:build`
Expected: writes `vendor/javascript/flow_dice_evaluator.js` (a few hundred KB). Confirm the file exists and is non-trivial: `wc -c vendor/javascript/flow_dice_evaluator.js`.

- [ ] **Step 3: Pin & import it.** In `config/importmap.rb`: `pin "flow_dice_evaluator"`. In `app/javascript/application.js` add (near the top): `import "flow_dice_evaluator"` — importing executes the bundle, which defines `window.FlowDice.evaluate` (per #3's entry).

- [ ] **Step 4: Freshness spec** `spec/flow_dice/opal_artifact_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"
require_relative "../../lib/flow_dice_opal"

RSpec.describe "Opal artifact" do
  it "vendor/javascript/flow_dice_evaluator.js is up to date with the engine" do
    committed = File.read(Rails.root.join("vendor/javascript/flow_dice_evaluator.js"))
    expect(FlowDiceOpal.build).to eq(committed),
      "Committed Opal artifact is stale — run `bundle exec rake opal:build` and commit the result."
  end
end
```
(If Opal output proves non-deterministic across runs, compare `Digest::SHA256` of the engine source files instead and note it; otherwise the exact-match is the strongest guard.)

- [ ] **Step 5: System spec — evaluator reaches the browser** `spec/system/evaluator_loaded_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Opal evaluator in the browser", type: :system do
  it "exposes window.FlowDice.evaluate" do
    visit "/"
    expect(page.evaluate_script("typeof window.FlowDice && typeof window.FlowDice.evaluate")).to eq("function")
  end
end
```

- [ ] **Step 6: Run & commit.** `bundle exec rspec spec/flow_dice/opal_artifact_spec.rb spec/system/evaluator_loaded_spec.rb` → green.
```bash
git add -A && git commit -m "feat(web): build and serve the Opal evaluator via importmap"
```

---

## Task 3: Roll pipeline (IndexedDB cache + /parse + crypto RNG)

**Files:** Create `app/javascript/roll_pipeline.js`, `spec/system/roll_pipeline_spec.rb`; Modify `config/importmap.rb`.

- [ ] **Step 1: Implement the pipeline** `app/javascript/roll_pipeline.js`:
```javascript
// Rolls dice notation client-side: cache plan (IndexedDB) -> /parse on miss ->
// FlowDice.evaluate with a crypto-backed RNG. No dependencies.

const DB_NAME = "flowdice";
const STORE = "plans";

function openDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function cacheGet(notation) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const r = db.transaction(STORE, "readonly").objectStore(STORE).get(notation);
    r.onsuccess = () => resolve(r.result || null);
    r.onerror = () => reject(r.error);
  });
}

async function cachePut(notation, entry) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const r = db.transaction(STORE, "readwrite").objectStore(STORE).put(entry, notation);
    r.onsuccess = () => resolve();
    r.onerror = () => reject(r.error);
  });
}

// Unbiased inclusive integer in [min, max] via rejection sampling (matches Ruby SecureRandom).
function secureInt(min, max) {
  const range = max - min + 1;
  const maxValid = Math.floor(0xffffffff / range) * range;
  const buf = new Uint32Array(1);
  let x;
  do { crypto.getRandomValues(buf); x = buf[0]; } while (x >= maxValid);
  return min + (x % range);
}

const secureRng = { int: (min, max) => secureInt(min, max) };

async function parse(notation) {
  const resp = await fetch("/parse", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ notation }),
  });
  const body = await resp.json();
  if (!resp.ok) throw new Error(body.error || "parse failed");
  return { plan: body.plan, explanation: body.explanation };
}

// Roll a notation. Returns { result, explanation }. Cached plans roll offline.
export async function rollNotation(notation) {
  let entry = await cacheGet(notation);
  if (!entry) {
    entry = await parse(notation);
    await cachePut(notation, entry);
  }
  const json = window.FlowDice.evaluate(JSON.stringify(entry.plan), notation, secureRng);
  return { result: JSON.parse(json), explanation: entry.explanation };
}
```

- [ ] **Step 2: Pin it.** In `config/importmap.rb`: `pin "roll_pipeline"`.

- [ ] **Step 3: System spec — full pipeline end-to-end** `spec/system/roll_pipeline_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "roll pipeline", type: :system do
  it "rolls a notation end-to-end (parse + cache + evaluate) in the browser" do
    visit "/"
    result = page.evaluate_async_script(<<~JS)
      const done = arguments[0];
      const m = await import("roll_pipeline");
      const { result } = await m.rollNotation("3d6");
      done(result);
    JS

    expect(result["kind"]).to eq("sum")
    expect(result["total"]).to be_between(3, 18)
    expect(result["dice"].length).to eq(3)
    expect(result["dice"].map { |d| d["value"] }).to all(be_between(1, 6))
  end

  it "re-rolls a cached notation without a second /parse" do
    visit "/"
    count = page.evaluate_async_script(<<~JS)
      const done = arguments[0];
      let parses = 0;
      const orig = window.fetch;
      window.fetch = (...a) => { if (String(a[0]).includes("/parse")) parses++; return orig(...a); };
      const m = await import("roll_pipeline");
      await m.rollNotation("2d20kh+5");
      await m.rollNotation("2d20kh+5");
      done(parses);
    JS
    expect(count).to eq(1) # parsed once, second roll used the cache
  end
end
```

- [ ] **Step 4: Run & commit.** `bundle exec rspec spec/system/roll_pipeline_spec.rb` → green.
```bash
git add -A && git commit -m "feat(web): client roll pipeline (IndexedDB cache + /parse + crypto RNG)"
```

---

## Task 4: Calculator markup + CSS

**Files:** Modify `app/views/home/index.html.erb`; Create `app/assets/stylesheets/calculator.css`; Modify `app/assets/stylesheets/application.css` (import calculator.css), `spec/system/calculator_view_spec.rb`.

- [ ] **Step 1: The view** `app/views/home/index.html.erb` (replace the placeholder):
```erb
<div class="fd" data-controller="calculator">
  <div class="fd-top">
    <div class="fd-brand">Flow<b>Dice</b></div>
    <div class="fd-tag">no dice? use flowdice</div>
  </div>
  <div class="fd-tabs">
    <div class="fd-tab on">Dice</div>
    <div class="fd-tab" aria-disabled="true">Favorites</div>
    <div class="fd-tab" aria-disabled="true">History</div>
  </div>
  <div class="fd-readout">
    <button class="fd-clr" data-action="calculator#clear" aria-label="Clear">×</button>
    <div class="fd-note" data-calculator-target="notation">d20</div>
  </div>
  <div class="fd-dice">
    <% [["d4","#ff5d5d"],["d6","#ff8a3d"],["d8","#f5b833"],["d10","#b6e34d"],["d12","#34d39b"],["d20","#38bdf8"],["d100","#8b9bff"],["d%","#f472d0"],["dN","#8a90a6"]].each do |name, color| %>
      <button class="fd-die" style="--c: <%= color %>" data-action="calculator#addDie" data-die="<%= name %>"><%= name %></button>
    <% end %>
  </div>
  <div class="fd-mods">
    <% %w[kh kl c C].each do |m| %>
      <button class="fd-mod" data-action="calculator#toggleMod" data-mod="<%= m %>"><%= m %></button>
    <% end %>
  </div>
  <div class="fd-step">
    <span class="fd-step-lbl">Modifier</span>
    <div class="fd-step-ctl">
      <button data-action="calculator#stepDown" aria-label="Decrease modifier">−</button>
      <b data-calculator-target="modifier">+0</b>
      <button data-action="calculator#stepUp" aria-label="Increase modifier">+</button>
    </div>
  </div>
  <div class="fd-action">
    <button class="fd-roll" data-action="calculator#roll" data-calculator-target="roll">ROLL</button>
    <button class="fd-fav" aria-disabled="true" aria-label="Save favorite (coming soon)">♥</button>
  </div>

  <div class="fd-sheet" data-calculator-target="sheet" hidden>
    <div class="fd-sheet-inner" data-calculator-target="sheetInner"></div>
  </div>
</div>
```

- [ ] **Step 2: The CSS** `app/assets/stylesheets/calculator.css` (plain CSS, approved design):
```css
.fd{max-width:430px;margin:0 auto;min-height:100vh;display:flex;flex-direction:column;padding:0 16px 22px;gap:14px;background:#0b0c10;color:#e8e9f0;font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
.fd-top{display:flex;align-items:baseline;justify-content:space-between;padding-top:18px}
.fd-brand{font-weight:800;font-size:20px;letter-spacing:-.02em;color:#fff}
.fd-brand b{color:#8b5cff}
.fd-tag{font-size:11px;color:#5d6175}
.fd-tabs{display:grid;grid-template-columns:repeat(3,1fr);gap:4px;background:#13141b;border-radius:13px;padding:4px}
.fd-tab{text-align:center;font-size:12.5px;font-weight:600;color:#7e8295;padding:8px 0;border-radius:10px}
.fd-tab.on{background:#262838;color:#fff}
.fd-tab[aria-disabled]{opacity:.5}
.fd-readout{position:relative;background:#13141b;border:1px solid #20222c;border-radius:18px;padding:18px;min-height:74px}
.fd-note{font-family:ui-monospace,"SF Mono",Menlo,monospace;font-size:31px;font-weight:600;letter-spacing:-.01em;color:#fff;font-variant-numeric:tabular-nums;line-height:1.15;word-break:break-all}
.fd-clr{position:absolute;top:15px;right:15px;width:30px;height:30px;border-radius:999px;background:#1d1f29;color:#9aa0b5;border:none;font-size:17px}
.fd-dice{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}
.fd-die{height:60px;border-radius:15px;background:#121319;border:1.5px solid var(--c);color:var(--c);font-weight:700;font-size:17px;font-family:ui-monospace,monospace}
.fd-mods{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}
.fd-mod{height:48px;border-radius:13px;background:#15161e;border:1px solid #262834;color:#cfd2e6;font-weight:600;font-size:14px;font-family:ui-monospace,monospace}
.fd-mod.on{background:rgba(139,92,255,.16);border-color:#8b5cff;color:#c5b6ff}
.fd-step{display:flex;align-items:center;justify-content:space-between;background:#13141b;border:1px solid #20222c;border-radius:14px;padding:10px 12px 10px 16px}
.fd-step-lbl{color:#868aa0;font-size:13px;font-weight:600}
.fd-step-ctl{display:flex;align-items:center;gap:12px}
.fd-step-ctl button{width:42px;height:42px;border-radius:12px;background:#1f2130;border:none;color:#cdd0e6;font-size:23px;font-weight:600}
.fd-step-ctl b{font-family:ui-monospace,monospace;font-size:20px;color:#fff;min-width:44px;text-align:center}
.fd-action{display:flex;gap:10px;margin-top:6px}
.fd-roll{flex:1;height:62px;border-radius:17px;background:#8b5cff;color:#fff;font-weight:800;font-size:19px;letter-spacing:.04em;border:none;box-shadow:0 8px 24px -8px rgba(139,92,255,.7)}
.fd-roll:disabled{opacity:.4;box-shadow:none}
.fd-fav{width:62px;height:62px;border-radius:17px;background:#15161e;border:1px solid #262834;color:#6a7a8c;font-size:22px;opacity:.5}
.fd-sheet{position:fixed;inset:0;background:rgba(6,7,10,.66);display:flex;align-items:flex-end;justify-content:center;z-index:50}
.fd-sheet[hidden]{display:none}
.fd-sheet-inner{width:100%;max-width:430px;background:#15161e;border:1px solid #2a2c38;border-radius:26px 26px 0 0;padding:18px 18px 26px;box-shadow:0 -24px 70px rgba(0,0,0,.55)}
.fd-rolled{text-align:center;color:#8b8fa3;font-family:ui-monospace,monospace;font-size:14px}
.fd-total{text-align:center;font-weight:800;font-size:94px;line-height:1;color:#fff;letter-spacing:-.03em;margin:4px 0 2px;font-variant-numeric:tabular-nums}
.fd-chips{display:flex;flex-wrap:wrap;gap:9px;justify-content:center;margin:16px 0 4px}
.fd-chip{min-width:50px;height:44px;padding:0 14px;display:flex;align-items:center;justify-content:center;border-radius:12px;background:#121319;border:1.5px solid var(--c,#2c2f3c);color:var(--c,#cfd2e6);font-weight:700;font-family:ui-monospace,monospace;font-size:16px}
.fd-chip.drop{opacity:.45;text-decoration:line-through;border-color:#3a3d4a;color:#7e8295}
.fd-brk{text-align:center;color:#7e8295;font-size:12.5px;margin-top:10px;font-family:ui-monospace,monospace}
.fd-sheet-act{display:flex;gap:10px;margin-top:22px}
.fd-again{flex:1;height:54px;border-radius:15px;background:#8b5cff;color:#fff;font-weight:800;font-size:16px;border:none}
.fd-ico{width:54px;height:54px;border-radius:15px;background:#1f2130;color:#cdd0e6;border:none;font-size:22px}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
body{margin:0;background:#0b0c10}
```

- [ ] **Step 3: Import the CSS.** In `app/assets/stylesheets/application.css` add: `/*= require calculator */` if using Sprockets directives, or (Propshaft) add `@import "calculator.css";` at the top of `application.css`. Verify which the app uses and apply the correct one (Propshaft default: `@import`).

- [ ] **Step 4: System spec** `spec/system/calculator_view_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "calculator view", type: :system do
  it "renders the dice buttons, readout, and ROLL" do
    visit "/"
    %w[d4 d6 d8 d10 d12 d20 d100 d% dN].each do |d|
      expect(page).to have_button(d)
    end
    expect(page).to have_button("ROLL")
    expect(page).to have_css(".fd-note")
  end
end
```

- [ ] **Step 5: Run & commit.** `bundle exec rspec spec/system/calculator_view_spec.rb` → green.
```bash
git add -A && git commit -m "feat(web): calculator markup + plain-CSS design"
```

---

## Task 5: Stimulus controller — build notation from taps

**Files:** Create `app/javascript/controllers/calculator_controller.js`; Create `spec/system/calculator_build_spec.rb`.

- [ ] **Step 1: The controller** `app/javascript/controllers/calculator_controller.js`:
```javascript
import { Controller } from "@hotwired/stimulus";

// Builds dice notation from taps. State: one "current die term" + a flat modifier.
// (Multi-term chaining and text entry are later increments; the server parser is
// the validator — a bad build surfaces as a 422 at roll time.)
export default class extends Controller {
  static targets = ["notation", "modifier", "roll", "sheet", "sheetInner"];

  connect() {
    this.die = null;     // e.g. "d20"
    this.count = 1;
    this.keep = null;    // "kh" | "kl"
    this.crit = null;    // "c" | "C"
    this.modifier = 0;
    this.render();
  }

  addDie(e) {
    const d = e.currentTarget.dataset.die;
    if (this.die === d) { this.count += 1; } else { this.die = d; this.count = 1; this.keep = null; this.crit = null; }
    this.render();
  }

  toggleMod(e) {
    const m = e.currentTarget.dataset.mod;
    if (m === "kh" || m === "kl") this.keep = this.keep === m ? null : m;
    else this.crit = this.crit === m ? null : m;
    this.render();
  }

  stepUp() { this.modifier += 1; this.render(); }
  stepDown() { this.modifier -= 1; this.render(); }
  clear() { this.die = null; this.count = 1; this.keep = null; this.crit = null; this.modifier = 0; this.render(); }

  notation() {
    if (!this.die) return "";
    let s = (this.count > 1 ? this.count : "") + this.die;
    if (this.keep) s += this.keep;
    if (this.crit) s += this.crit;
    if (this.modifier > 0) s += "+" + this.modifier;
    else if (this.modifier < 0) s += "-" + Math.abs(this.modifier);
    return s;
  }

  render() {
    const n = this.notation();
    this.notationTarget.textContent = n || "—";
    this.modifierTarget.textContent = (this.modifier >= 0 ? "+" : "") + this.modifier;
    this.rollTarget.disabled = !n;
    this.element.querySelectorAll(".fd-mod").forEach((b) => {
      const m = b.dataset.mod;
      b.classList.toggle("on", m === this.keep || m === this.crit);
    });
  }
}
```

- [ ] **Step 2: System spec** `spec/system/calculator_build_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "building notation", type: :system do
  it "builds notation from taps" do
    visit "/"
    find("button[data-die='d20']").click
    find("button[data-die='d20']").click
    expect(find(".fd-note")).to have_text("2d20")
    find("button[data-mod='kh']").click
    expect(find(".fd-note")).to have_text("2d20kh")
    find("button[aria-label='Increase modifier']").click
    find("button[aria-label='Increase modifier']").click
    expect(find(".fd-note")).to have_text("2d20kh+2")
    find("button[aria-label='Clear']").click
    expect(find(".fd-note")).to have_text("—")
  end
end
```

- [ ] **Step 3: Run & commit.** `bundle exec rspec spec/system/calculator_build_spec.rb` → green.
```bash
git add -A && git commit -m "feat(web): Stimulus calculator controller (tap to build notation)"
```

---

## Task 6: Wire ROLL → pipeline → result sheet

**Files:** Modify `app/javascript/controllers/calculator_controller.js`; Create `spec/system/roll_flow_spec.rb`.

- [ ] **Step 1: Add rolling to the controller.** Add an import at the top: `import { rollNotation } from "roll_pipeline";` and these methods to the controller class:
```javascript
  async roll() {
    const n = this.notation();
    if (!n) return;
    this.rollTarget.disabled = true;
    try {
      const { result } = await rollNotation(n);
      this.renderSheet(result);
    } catch (err) {
      this.notationTarget.textContent = err.message;
    } finally {
      this.rollTarget.disabled = false;
    }
  }

  renderSheet(result) {
    const chips = result.dice.map((d) =>
      `<div class="fd-chip ${d.kept ? "" : "drop"}" style="--c: ${dieColor(d.die)}">${d.value}</div>`
    ).join("");
    this.sheetInnerTarget.innerHTML =
      `<div class="fd-rolled">${result.notation}</div>` +
      `<div class="fd-total">${result.total}</div>` +
      `<div class="fd-chips">${chips}</div>` +
      `<div class="fd-brk">${result.breakdown}</div>` +
      `<div class="fd-sheet-act">` +
        `<button class="fd-again" data-action="calculator#roll">Roll again</button>` +
        `<button class="fd-ico" data-action="calculator#closeSheet">×</button>` +
      `</div>`;
    this.sheetTarget.hidden = false;
  }

  closeSheet() { this.sheetTarget.hidden = true; }
```
And add the color helper at module scope (above the class):
```javascript
const DIE_COLORS = { d4:"#ff5d5d", d6:"#ff8a3d", d8:"#f5b833", d10:"#b6e34d", d12:"#34d39b", d20:"#38bdf8", d100:"#8b9bff" };
function dieColor(die) {
  if (die && die.startsWith("d%")) return "#f472d0";
  return DIE_COLORS[die] || "#8a90a6";
}
```
(Add `closeSheet` to `static targets`? No — it's an action, not a target. The sheet/sheetInner targets already exist from Task 4.)

- [ ] **Step 2: System spec** `spec/system/roll_flow_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "rolling", type: :system do
  it "rolls and shows a result sheet with a total in range" do
    visit "/"
    find("button[data-die='d20']").click
    click_button "ROLL"
    expect(page).to have_css(".fd-total")
    total = find(".fd-total").text.to_i
    expect(total).to be_between(1, 20)
    expect(page).to have_css(".fd-chip", count: 1)
    click_button "×"
    expect(page).to have_no_css(".fd-total")
  end
end
```

- [ ] **Step 3: Run & commit.** `bundle exec rspec spec/system/roll_flow_spec.rb` → green.
```bash
git add -A && git commit -m "feat(web): wire ROLL to the pipeline and render the result sheet"
```

---

## Task 7: Result polish — kept/dropped + percentile

**Files:** Modify `spec/system/roll_flow_spec.rb` (add cases). (The rendering from Task 6 already handles kept/dropped via the `drop` class and `d%` via `dieColor`; these specs lock the behavior — adjust the renderer only if a spec fails.)

- [ ] **Step 1: Add cases** to `spec/system/roll_flow_spec.rb` inside the describe block:
```ruby
  it "marks dropped dice on a keep roll (2d20kh)" do
    visit "/"
    find("button[data-die='d20']").click
    find("button[data-die='d20']").click
    find("button[data-mod='kh']").click
    click_button "ROLL"
    expect(page).to have_css(".fd-chip", count: 2)
    expect(page).to have_css(".fd-chip.drop", count: 1) # one die dropped
  end

  it "shows tens and units for a percentile roll (d%)" do
    visit "/"
    find("button[data-die='d%']").click
    click_button "ROLL"
    expect(page).to have_css(".fd-chip", count: 2)             # d%(tens) + d%(units)
    total = find(".fd-total").text.to_i
    expect(total).to be_between(1, 100)
  end
```

- [ ] **Step 2: Run.** `bundle exec rspec spec/system/roll_flow_spec.rb` → all green. If a case fails, fix `renderSheet`/`dieColor` in the controller (do not weaken the assertion).

- [ ] **Step 3: Commit.**
```bash
git add -A && git commit -m "test(system): lock kept/dropped + percentile result rendering"
```

---

## Final verification (after Task 7)

- [ ] `bundle exec rspec` → full suite green (105 from #3 + the new system/artifact specs).
- [ ] `bin/packwerk check` → `No offenses detected`.
- [ ] `bin/rails zeitwerk:check` → `All is good!`.
- [ ] Manual/preview sanity: `preview_start` + screenshot the real `/` — it should match the approved mockup, and a roll should show the result sheet.

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| A — visual design (dark/violet, color-coded dice, lean input, result sheet) | 4 (markup+CSS), 5 (input), 6–7 (sheet) |
| B — Opal artifact (rake build, importmap pin, committed + freshness check) | 2 |
| C — roll pipeline (IndexedDB cache, /parse on miss, crypto RNG rejection-sampling, evaluate, offline re-roll) | 3 |
| D — Stimulus controller (tap-to-build, kh/kl/c/C, stepper, clear, roll, 422 surfaced) | 5, 6 |
| E — routes/views (`/` Dice built; Favorites/History inert) | 4 |
| F — result rendering (total, kept/dropped chips, d% tens/units, breakdown, roll-again/close) | 6, 7 |
| G — testing (Capybara+cuprite system specs; artifact freshness; structure/range assertions) | 1–7 |
| H — offline re-rolls (cached plan) | 3 (the cached-reroll spec) |

The `123` full-number-pad toggle (Section A) is intentionally **deferred within #4** — the lean controls (dice tap + stepper) cover all core notation; multi-digit counts/modifiers via the pad are a fast-follow. Flagged here rather than silently dropped. Live-as-you-type explanation = #8.

**Placeholder scan:** none — every code step is concrete. The "adjust if a spec fails" notes (Tasks 4 Step 3, 7) pair with a concrete starting implementation + a test oracle.

**Type/name consistency:** `rollNotation(notation) -> {result, explanation}` is consistent across `roll_pipeline.js` (Task 3) and the controller (Task 6); `window.FlowDice.evaluate(planJson, notation, rng)` matches #3; the result shape `{kind,total,notation,dice:[{die,value,kept}],breakdown}` matches the evaluator and the renderer; Stimulus targets (`notation`/`modifier`/`roll`/`sheet`/`sheetInner`) match between the view (Task 4) and controller (Tasks 5–6); the dice color map matches the approved palette.
