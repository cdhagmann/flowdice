# frozen_string_literal: true

require "rails_helper"

RSpec.describe "smoke", type: :system do
  it "loads the home page in a real browser" do
    visit "/"
    expect(page).to have_content("FlowDice")
  end
end
