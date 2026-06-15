# frozen_string_literal: true

# Stateless JSON API: parses dice notation into a plan + explanation.
# Inherits ActionController::API (no CSRF / no browser gate / no view layer).
class ParseController < ActionController::API
  def create
    parsed = FlowDice::Engine.parse(params.require(:notation))
    render json: {
      notation: parsed.notation,
      plan: parsed.plan,
      explanation: parsed.explanation
    }
  rescue FlowDice::ParseError, ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :unprocessable_content
  end
end
