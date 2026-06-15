import { Controller } from "@hotwired/stimulus";
import { rollNotation } from "roll_pipeline";

const DIE_COLORS = { d4:"#ff5d5d", d6:"#ff8a3d", d8:"#f5b833", d10:"#b6e34d", d12:"#34d39b", d20:"#38bdf8", d100:"#8b9bff" };
function dieColor(die) {
  if (die && die.startsWith("d%")) return "#f472d0";
  return DIE_COLORS[die] || "#8a90a6";
}

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

  buildNotation() {
    if (!this.die) return "";
    let s = (this.count > 1 ? this.count : "") + this.die;
    if (this.keep) s += this.keep;
    if (this.crit) s += this.crit;
    if (this.modifier > 0) s += "+" + this.modifier;
    else if (this.modifier < 0) s += "-" + Math.abs(this.modifier);
    return s;
  }

  async roll() {
    const n = this.buildNotation();
    if (!n || this.rolling) return;
    this.rolling = true;
    this.rollTarget.disabled = true;
    try {
      const { result } = await rollNotation(n);
      this.renderSheet(result);
    } catch (err) {
      this.notationTarget.textContent = err.message;
    } finally {
      this.rolling = false;
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

  render() {
    const n = this.buildNotation();
    this.notationTarget.textContent = n || "—";
    this.modifierTarget.textContent = (this.modifier >= 0 ? "+" : "") + this.modifier;
    this.rollTarget.disabled = !n;
    this.element.querySelectorAll(".fd-mod").forEach((b) => {
      const m = b.dataset.mod;
      b.classList.toggle("on", m === this.keep || m === this.crit);
    });
  }
}
