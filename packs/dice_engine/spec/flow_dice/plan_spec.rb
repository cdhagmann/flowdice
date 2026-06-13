# frozen_string_literal: true

RSpec.describe FlowDice::Plan do
  it "builds a dice node with defaults" do
    node = described_class.dice(die_kind: :standard, faces: 20, count: 2, label: "d20")
    expect(node).to eq(
      type: :dice, die_kind: :standard, faces: 20, count: 2, keep: nil, label: "d20"
    )
  end

  it "builds a dice node with a keep clause" do
    node = described_class.dice(
      die_kind: :standard, faces: 20, count: 2, label: "d20",
      keep: { mode: :high, n: 1 }
    )
    expect(node[:keep]).to eq(mode: :high, n: 1)
  end

  it "builds const, binary, and crit nodes" do
    c = described_class.const(5)
    b = described_class.binary(:+, c, c)
    k = described_class.crit(:normal, c)

    expect(c).to eq(type: :const, value: 5)
    expect(b).to eq(type: :binary, op: :+, left: c, right: c)
    expect(k).to eq(type: :crit, mode: :normal, child: c)
  end
end
