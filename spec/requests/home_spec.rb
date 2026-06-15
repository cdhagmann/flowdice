# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /", type: :request do
  it "renders the placeholder home page" do
    get "/"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("FlowDice")
  end
end
