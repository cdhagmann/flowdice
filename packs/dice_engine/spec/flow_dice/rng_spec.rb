# frozen_string_literal: true

RSpec.describe FlowDice::SecureRandomRng do
  subject(:rng) { described_class.new }

  it "returns integers within the inclusive range" do
    200.times do
      v = rng.int(1, 6)
      expect(v).to be_between(1, 6)
    end
  end

  it "can return the only value when min == max" do
    expect(rng.int(4, 4)).to eq(4)
  end

  it "raises when min > max" do
    expect { rng.int(6, 1) }.to raise_error(ArgumentError)
  end

  it "covers both endpoints over many draws" do
    seen = Array.new(2000) { rng.int(0, 1) }.uniq.sort
    expect(seen).to eq([0, 1])
  end
end
