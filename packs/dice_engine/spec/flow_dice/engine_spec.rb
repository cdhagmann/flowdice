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
