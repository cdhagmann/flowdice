# frozen_string_literal: true

module FlowDice
  ParseResult = Struct.new(:notation, :plan, :explanation) unless defined?(ParseResult)
  Result = Struct.new(:kind, :total, :notation, :dice, :breakdown) unless defined?(Result)

  # Walks a plan tree against an injected RNG. Plain Opal-safe Ruby — this file
  # is compiled to JS via Opal in increment #3.
  module Evaluator
    module_function

    def evaluate(parsed, rng: SecureRandomRng.new)
      dice = []
      total = eval_node(parsed.plan, rng, dice)
      Result.new(:sum, total, parsed.notation, dice, build_breakdown(dice, total))
    end

    def eval_node(node, rng, dice)
      case node[:type]
      when :const  then node[:value]
      when :binary then eval_binary(node, rng, dice)
      when :dice   then eval_dice(node, rng, dice)
      else raise ArgumentError, "unknown node type: #{node[:type].inspect}"
      end
    end

    def eval_binary(node, rng, dice)
      left = eval_node(node[:left], rng, dice)
      right = eval_node(node[:right], rng, dice)
      node[:op] == :+ ? left + right : left - right
    end

    def eval_dice(node, rng, dice)
      rolls = Array.new(node[:count]) { roll_one(node[:faces], rng) }
      rolls.each { |v| dice << { die: node[:label], value: v, kept: true } }
      rolls.sum
    end

    def roll_one(faces, rng)
      faces.is_a?(Array) ? faces[rng.int(0, faces.length - 1)] : rng.int(1, faces)
    end

    def build_breakdown(dice, total)
      return total.to_s if dice.empty?

      parts = dice.map { |d| d[:kept] ? d[:value].to_s : "#{d[:value]} (dropped)" }
      "#{parts.join(', ')} = #{total}"
    end
  end
end
