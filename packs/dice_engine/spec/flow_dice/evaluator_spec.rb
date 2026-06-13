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
end

RSpec::Matchers.define :be_present_string do
  match { |s| s.is_a?(String) && !s.strip.empty? }
end
