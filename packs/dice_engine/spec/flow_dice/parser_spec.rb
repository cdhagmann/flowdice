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
