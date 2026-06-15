# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Opal evaluator in the browser", type: :system do
  it "exposes window.FlowDice.evaluate" do
    visit "/"
    expect(page.evaluate_script("typeof window.FlowDice && typeof window.FlowDice.evaluate")).to eq("function")
  end
end
