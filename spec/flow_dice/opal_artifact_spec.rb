# frozen_string_literal: true

require "rails_helper"
require_relative "../../lib/flow_dice_opal"

RSpec.describe "Opal artifact" do
  it "vendor/javascript/flow_dice_evaluator.js is up to date with the engine" do
    committed = File.read(Rails.root.join("vendor/javascript/flow_dice_evaluator.js"))
    expect(FlowDiceOpal.build).to eq(committed),
      "Committed Opal artifact is stale — run `bundle exec rake opal:build` and commit the result."
  end
end
