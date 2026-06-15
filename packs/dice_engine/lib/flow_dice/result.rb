# frozen_string_literal: true

module FlowDice
  # Result of evaluating a plan against an RNG.
  Result = Struct.new(:kind, :total, :notation, :dice, :breakdown)
end
