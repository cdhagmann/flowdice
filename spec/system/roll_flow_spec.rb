# frozen_string_literal: true

require "rails_helper"

RSpec.describe "rolling", type: :system do
  it "rolls and shows a result sheet with a total in range" do
    visit "/"
    find("button[data-die='d20']").click
    click_button "ROLL"
    expect(page).to have_css(".fd-total")
    total = find(".fd-total").text.to_i
    expect(total).to be_between(1, 20)
    expect(page).to have_css(".fd-chip", count: 1)
    find(".fd-ico").click
    expect(page).to have_no_css(".fd-total")
  end

  it "marks dropped dice on a keep roll (2d20kh)" do
    visit "/"
    find("button[data-die='d20']").click
    find("button[data-die='d20']").click
    find("button[data-mod='kh']").click
    click_button "ROLL"
    expect(page).to have_css(".fd-chip", count: 2)
    expect(page).to have_css(".fd-chip.drop", count: 1)
  end

  it "shows tens and units for a percentile roll (d%)" do
    visit "/"
    find("button[data-die='d%']").click
    click_button "ROLL"
    expect(page).to have_css(".fd-chip", count: 2)
    total = find(".fd-total").text.to_i
    expect(total).to be_between(1, 100)
  end
end
