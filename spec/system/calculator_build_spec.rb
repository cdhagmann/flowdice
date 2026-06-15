# frozen_string_literal: true

require "rails_helper"

RSpec.describe "building notation", type: :system do
  it "builds notation from taps" do
    visit "/"
    find("button[data-die='d20']").click
    find("button[data-die='d20']").click
    expect(find(".fd-note")).to have_text("2d20")
    find("button[data-mod='kh']").click
    expect(find(".fd-note")).to have_text("2d20kh")
    find("button[aria-label='Increase modifier']").click
    find("button[aria-label='Increase modifier']").click
    expect(find(".fd-note")).to have_text("2d20kh+2")
    find("button[aria-label='Clear']").click
    expect(find(".fd-note")).to have_text("—")
  end

  it "disables ROLL when the notation is empty" do
    visit "/"
    expect(page).to have_button("ROLL", disabled: true)
    find("button[data-die='d6']").click
    expect(page).to have_button("ROLL", disabled: false)
  end
end
