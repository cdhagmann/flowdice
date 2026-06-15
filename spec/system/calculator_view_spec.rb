# frozen_string_literal: true

require "rails_helper"

RSpec.describe "calculator view", type: :system do
  it "renders the dice buttons, readout, and ROLL" do
    visit "/"
    %w[d4 d6 d8 d10 d12 d20 d100 d% dN].each do |d|
      expect(page).to have_button(d)
    end
    expect(page).to have_button("ROLL")
    expect(page).to have_css(".fd-note")
  end
end
