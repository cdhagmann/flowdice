# frozen_string_literal: true

require "strscan"

module FlowDice
  # Recursive-descent parser: notation String -> plan tree (Plan nodes).
  # Server-side only (uses StringScanner); never compiled to Opal.
  class Parser
    def self.parse(notation)
      new(notation).parse
    end

    def initialize(notation)
      @source = notation.to_s
      @ss = StringScanner.new(@source.gsub(/\s+/, ""))
    end

    def parse
      raise ParseError, "empty notation" if @ss.eos?

      node = expression
      raise ParseError, "unexpected input: #{@ss.rest.inspect}" unless @ss.eos?

      node
    end

    private

    def expression
      node = term
      while (op = @ss.scan(/[+\-]/))
        node = Plan.binary(op == "+" ? :+ : :-, node, term)
      end
      node
    end

    def term
      if (num = @ss.scan(/\d+/))
        @ss.check(/d/) ? dice_expr(num.to_i) : Plan.const(num.to_i)
      elsif @ss.check(/d/)
        dice_expr(1)
      else
        raise ParseError, "expected a number or die at #{@ss.rest.inspect}"
      end
    end

    def dice_expr(count)
      die = die_type(count)
      die = apply_keep(die)
      apply_crit(die)
    end

    def apply_keep(die)
      if @ss.scan(/kh/)
        die.merge(keep: { mode: :high, n: (@ss.scan(/\d+/) || "1").to_i })
      elsif @ss.scan(/kl/)
        die.merge(keep: { mode: :low, n: (@ss.scan(/\d+/) || "1").to_i })
      else
        die
      end
    end

    def apply_crit(die)
      if @ss.scan(/c/)
        Plan.crit(:normal, die)
      elsif @ss.scan(/C/)
        Plan.crit(:perkins, die)
      else
        die
      end
    end

    def die_type(count)
      @ss.scan(/d/) || raise(ParseError, "expected 'd'")

      if (n = @ss.scan(/\d+/))
        Plan.dice(die_kind: :standard, faces: n.to_i, count: count, label: "d#{n}")
      else
        raise ParseError, "invalid die type at #{@ss.rest.inspect}"
      end
    end
  end
end
