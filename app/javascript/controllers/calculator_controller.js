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

  buildNotation() {
    if (!this.die) return "";
    let s = (this.count > 1 ? this.count : "") + this.die;
    if (this.keep) s += this.keep;
    if (this.crit) s += this.crit;
    if (this.modifier > 0) s += "+" + this.modifier;
    else if (this.modifier < 0) s += "-" + Math.abs(this.modifier);
    return s;
  }

  roll() { /* wired in Task 6 */ }

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
