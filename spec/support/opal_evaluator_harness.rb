# frozen_string_literal: true

require_relative "../../lib/flow_dice_opal"
require "mini_racer"

# Compiles the Opal evaluator entry once and runs rolls through it in V8.
module OpalEvaluatorHarness
  module_function

  def compiled_js
    @compiled_js ||= FlowDiceOpal.build
  end

  def context
    ctx = MiniRacer::Context.new
    ctx.eval(compiled_js)
    ctx
  end

  # Roll a Ruby plan hash + notation through the JS evaluator with a fixed RNG
  # draw sequence. Returns the parsed result hash (string keys).
  def js_roll(plan, notation, rng_values, ctx: context())
    ctx.eval(<<~JS)
      globalThis.__seq = #{rng_values.to_json};
      globalThis.__rng = { int: function (min, max) { return globalThis.__seq.shift(); } };
    JS
    json = ctx.eval(
      "FlowDice.evaluate(#{plan.to_json.to_json}, #{notation.to_json}, globalThis.__rng)"
    )
    JSON.parse(json)
  end
end
