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

  it "explains adding a second dice term without a doubled 'roll'" do
    expect(explain("2d6+1d4")).to eq("Roll 2d6, plus d4")
  end

  it "explains subtracting a second dice term" do
    expect(explain("2d6-1d4")).to eq("Roll 2d6, minus d4")
  end

  it "raises on an unknown binary op" do
    bad = { type: :binary, op: :*, left: FlowDice::Plan.const(1), right: FlowDice::Plan.const(2) }
    expect { FlowDice::Explanation.generate(bad) }.to raise_error(ArgumentError)
  end

  it "raises on an unknown crit mode" do
    bad = { type: :crit, mode: :wild, child: FlowDice::Plan.dice(die_kind: :standard, faces: 6, count: 1, label: "d6") }
    expect { FlowDice::Explanation.generate(bad) }.to raise_error(ArgumentError)
  end
end
