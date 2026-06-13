# frozen_string_literal: true

module FlowDice
  # Walks a plan tree against an injected RNG. Plain Opal-safe Ruby — this file
  # is compiled to JS via Opal in increment #3.
  module Evaluator
    module_function

    def evaluate(parsed, rng:)
      dice = []
      total = eval_node(parsed.plan, rng, dice)
      Result.new(:sum, total, parsed.notation, dice, build_breakdown(dice, total))
    end

    def eval_node(node, rng, dice)
      case node[:type]
      when :const  then node[:value]
      when :binary then eval_binary(node, rng, dice)
      when :dice   then eval_dice(node, rng, dice)
      when :crit   then eval_crit(node, rng, dice)
      else raise ArgumentError, "unknown node type: #{node[:type].inspect}"
      end
    end

    def eval_binary(node, rng, dice)
      left = eval_node(node[:left], rng, dice)
      right = eval_node(node[:right], rng, dice)
      node[:op] == :+ ? left + right : left - right
    end

    def eval_dice(node, rng, dice)
      return eval_percentile(node, rng, dice) if node[:die_kind] == :percentile

      rolls = Array.new(node[:count]) { roll_one(node[:faces], rng) }
      kept = keep_flags(rolls, node[:keep])
      total = 0
      rolls.each_with_index do |v, i|
        dice << { die: node[:label], value: v, kept: kept[i] }
        total += v if kept[i]
      end
      total
    end

    def eval_percentile(node, rng, dice)
      tens = Array.new(node[:count]) { rng.int(0, 9) * 10 }
      units = rng.int(0, 9)
      keep = node[:keep] || { mode: :high, n: 1 } # count == 1 selects the only tens
      order = (0...tens.length).sort_by { |i| tens[i] }
      kept_index = keep[:mode] == :high ? order.last : order.first

      tens.each_with_index do |t, i|
        dice << { die: "d%(tens)", value: t, kept: i == kept_index }
      end
      dice << { die: "d%(units)", value: units, kept: true }

      value = tens[kept_index] + units
      value.zero? ? 100 : value
    end

    # Returns an array of booleans (one per roll) marking which dice are kept.
    def keep_flags(rolls, keep)
      return Array.new(rolls.length, true) if keep.nil?

      order = (0...rolls.length).sort_by { |i| rolls[i] } # ascending by value
      selected = keep[:mode] == :high ? order.last(keep[:n]) : order.first(keep[:n])
      Array.new(rolls.length) { |i| selected.include?(i) }
    end

    def roll_one(faces, rng)
      faces.is_a?(Array) ? faces[rng.int(0, faces.length - 1)] : rng.int(1, faces)
    end

    def eval_crit(node, rng, dice)
      child = node[:child]
      case node[:mode]
      when :normal
        eval_dice(child.merge(count: child[:count] * 2), rng, dice)
      when :perkins
        max_set = child[:count] * max_face(child[:faces])
        max_set + eval_dice(child, rng, dice)
      else
        raise ArgumentError, "unknown crit mode: #{node[:mode].inspect}"
      end
    end

    def max_face(faces)
      faces.is_a?(Array) ? faces.max : faces
    end

    def build_breakdown(dice, total)
      return total.to_s if dice.empty?

      parts = dice.map { |d| d[:kept] ? d[:value].to_s : "#{d[:value]} (dropped)" }
      "#{parts.join(', ')} = #{total}"
    end
  end
end
