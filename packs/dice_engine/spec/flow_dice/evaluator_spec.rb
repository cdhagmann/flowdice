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
