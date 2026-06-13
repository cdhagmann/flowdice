# frozen_string_literal: true

require_relative "../fixtures/golden_rolls"

RSpec.describe "golden rolls" do
  FlowDice::GOLDEN_ROLLS.each do |c|
    it "#{c[:notation]} with rng #{c[:rng].inspect} totals #{c[:total]}" do
      result = FlowDice::Engine.roll(c[:notation], rng: FlowDice::SequenceRng.new(c[:rng]))
      expect(result.total).to eq(c[:total])
      expect(result.dice.select { |d| d[:kept] }.map { |d| d[:value] }).to eq(c[:kept])
    end
  end
end
