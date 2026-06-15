# backtick_javascript: true
# frozen_string_literal: true

# Compiled to JS by Opal. NOT autoloaded by Rails (Zeitwerk ignores flow_dice/opal/).
# Explicit requires because Zeitwerk stripped the engine's require-chain. Excludes
# secure_random_rng (SecureRandom is unavailable in Opal); the RNG is injected from JS.
require "json"
require "flow_dice/result"
require "flow_dice/parse_result"
require "flow_dice/evaluator"

module FlowDice
  # Adapts a JS rng object (with int(min,max)) to the Ruby rng interface the
  # evaluator calls. `.to_i` guards against JS numbers arriving as floats.
  class JsRng
    def initialize(native)
      @native = native
    end

    def int(min, max)
      `#{@native}.int(#{min}, #{max})`.to_i
    end
  end

  module OpalEntry
    module_function

    # Recursively: symbolize hash keys; symbolize string values EXCEPT under :label.
    def symbolize(node)
      case node
      when Hash
        node.each_with_object({}) do |(k, v), out|
          key = k.to_sym
          out[key] = key == :label ? v : symbolize(v)
        end
      when Array
        node.map { |e| symbolize(e) }
      when String
        node.to_sym
      else
        node
      end
    end

    # plan_json: JSON String; notation: String; js_rng: JS object with int(min,max).
    # Returns the result as a JSON String.
    def evaluate(plan_json, notation, js_rng)
      plan = symbolize(JSON.parse(plan_json))
      result = Evaluator.evaluate(
        ParseResult.new(notation, plan, nil),
        rng: JsRng.new(js_rng)
      )
      {
        kind: result.kind.to_s,
        total: result.total,
        notation: result.notation,
        dice: result.dice,
        breakdown: result.breakdown
      }.to_json
    end
  end
end

# Expose to JS using the proven plain-JS-backtick delegation (NO nested Ruby interp):
`globalThis.FlowDice = { evaluate: function(planJson, notation, rng) { return Opal.FlowDice.OpalEntry.$evaluate(planJson, notation, rng); } }`
