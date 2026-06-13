# frozen_string_literal: true

module FlowDice
  # Plan tree -> plain-English explanation. Server-side only.
  module Explanation
    module_function

    def generate(node)
      text = render(node)
      text.sub(/\A./, &:upcase)
    end

    def render(node)
      case node[:type]
      when :const  then node[:value].to_s
      when :binary then render_binary(node)
      when :crit   then "#{render(node[:child])} (#{node[:mode] == :perkins ? 'Perkins' : 'normal'} crit)"
      when :dice   then render_dice(node)
      else raise ArgumentError, "unknown node type: #{node[:type].inspect}"
      end
    end

    def render_binary(node)
      left = render(node[:left])
      right = node[:right]
      if right[:type] == :const
        verb = node[:op] == :+ ? "add" : "subtract"
        "#{left}, #{verb} #{right[:value]}"
      else
        conj = node[:op] == :+ ? "plus" : "minus"
        "#{left}, #{conj} #{render(right)}"
      end
    end

    def render_dice(node)
      phrase = "roll #{dice_phrase(node)}"
      phrase += keep_phrase(node[:keep]) if node[:keep] && node[:die_kind] != :percentile
      phrase
    end

    def dice_phrase(node)
      case node[:die_kind]
      when :percentile
        node[:count] > 1 ? "percentile#{percentile_keep_phrase(node)}" : "percentile"
      when :custom
        if (m = node[:label].match(/\Ad\[(-?\d+)\.\.(-?\d+)\]\z/))
          "#{node[:count]} #{node[:count] == 1 ? 'die' : 'dice'} (#{m[1]}–#{m[2]})"
        else
          "#{count_prefix(node[:count])}#{node[:label]}"
        end
      else
        "#{count_prefix(node[:count])}d#{node[:faces]}"
      end
    end

    def count_prefix(count)
      count == 1 ? "" : count.to_s
    end

    def keep_phrase(keep)
      which = keep[:mode] == :high ? "highest" : "lowest"
      keep[:n] == 1 ? ", keep the #{which}" : ", keep the #{which} #{keep[:n]}"
    end

    def percentile_keep_phrase(node)
      extra = node[:count] - 1
      kind = node[:keep] && node[:keep][:mode] == :high ? "penalty" : "bonus"
      " with #{extra} #{kind} #{extra == 1 ? 'die' : 'dice'}"
    end
  end
end
