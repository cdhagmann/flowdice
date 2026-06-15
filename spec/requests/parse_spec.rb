# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /parse", type: :request do
  it "returns the plan and explanation for valid notation" do
    post "/parse", params: { notation: "2d20kh+5" }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["notation"]).to eq("2d20kh+5")
    expect(body["explanation"]).to eq("Roll 2d20, keep the highest, add 5")
    expect(body["plan"]["type"]).to eq("binary")
    expect(body["plan"]["op"]).to eq("+")
    expect(body["plan"]["left"]["type"]).to eq("dice")
  end

  it "returns 422 with an error for invalid notation" do
    post "/parse", params: { notation: "d" }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to be_a(String)
  end

  it "returns 422 when notation is missing" do
    post "/parse", params: {}

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
