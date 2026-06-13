# frozen_string_literal: true

module FlowDice
  # Public API for the dice engine.
  module Engine
    module_function

    def parse(notation)
      plan = Parser.parse(notation)
      ParseResult.new(notation, plan, Explanation.generate(plan))
    end

    def evaluate(parsed, rng: SecureRandomRng.new)
      Evaluator.evaluate(parsed, rng: rng)
    end

    def explain(notation)
      parse(notation).explanation
    end

    def roll(notation, rng: SecureRandomRng.new)
      evaluate(parse(notation), rng: rng)
    end
  end
end
