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

  it "rejects a zero-face standard die" do
    expect { parse("d0") }.to raise_error(FlowDice::ParseError)
  end
end
