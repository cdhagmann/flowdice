# frozen_string_literal: true

class ParseController < ApplicationController
  # Stateless JSON API; no CSRF token (no session/mutation).
  skip_forgery_protection

  def create
    parsed = FlowDice::Engine.parse(params.require(:notation))
    render json: {
      notation: parsed.notation,
      plan: parsed.plan,
      explanation: parsed.explanation
    }
  rescue FlowDice::ParseError, ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
