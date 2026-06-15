# frozen_string_literal: true

require "rails_helper"
require_relative "../fixtures/golden_rolls"

RSpec.describe "Opal/Ruby evaluator parity" do
  FlowDice::GOLDEN_ROLLS.each do |c|
    it "#{c[:notation]} (rng #{c[:rng].inspect}) matches Ruby and the fixture" do
      plan = FlowDice::Engine.parse(c[:notation]).plan

      ruby = FlowDice::Engine.roll(c[:notation], rng: FlowDice::SequenceRng.new(c[:rng].dup))
      js   = OpalEvaluatorHarness.js_roll(plan, c[:notation], c[:rng].dup)

      js_kept = js["dice"].select { |d| d["kept"] }.map { |d| d["value"] }

      # JS == fixture
      expect(js["total"]).to eq(c[:total])
      expect(js_kept).to eq(c[:kept])
      # JS == Ruby
      expect(js["total"]).to eq(ruby.total)
      expect(js_kept).to eq(ruby.dice.select { |d| d[:kept] }.map { |d| d[:value] })
    end
  end

  it "agrees with Ruby on a percentile pair (symbolize boundary: die_kind/keep.mode)" do
    plan = FlowDice::Engine.parse("2d%kl").plan
    js = OpalEvaluatorHarness.js_roll(plan, "2d%kl", [7, 4, 3])
    expect(js["total"]).to eq(43)
    expect(js["dice"].map { |d| [d["die"], d["value"], d["kept"]] }).to eq([
      ["d%(tens)", 70, false], ["d%(tens)", 40, true], ["d%(units)", 3, true]
    ])
  end

  it "agrees with Ruby on a crit (symbolize boundary: op/mode symbols)" do
    plan = FlowDice::Engine.parse("d12C+5").plan
    js = OpalEvaluatorHarness.js_roll(plan, "d12C+5", [7])
    expect(js["total"]).to eq(24) # 12 (max d12) + 7 + 5
  end
end
