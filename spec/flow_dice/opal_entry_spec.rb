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
