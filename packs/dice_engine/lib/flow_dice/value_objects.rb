# frozen_string_literal: true

module FlowDice
  # Public value objects returned by the engine.
  ParseResult = Struct.new(:notation, :plan, :explanation)
  Result = Struct.new(:kind, :total, :notation, :dice, :breakdown)
end
