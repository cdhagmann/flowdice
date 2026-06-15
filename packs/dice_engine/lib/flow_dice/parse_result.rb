# frozen_string_literal: true

module FlowDice
  # Result of parsing: the source notation, the plan tree, and the explanation.
  ParseResult = Struct.new(:notation, :plan, :explanation)
end
