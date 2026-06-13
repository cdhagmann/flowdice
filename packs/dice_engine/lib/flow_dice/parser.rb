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

      if @ss.scan(/%/)
        Plan.dice(die_kind: :percentile, faces: 100, count: count, label: "d%")
      elsif @ss.scan(/\{/)
        faces = face_set
        Plan.dice(die_kind: :custom, faces: faces, count: count, label: "d{#{faces.join(',')}}")
      elsif @ss.scan(/\[/)
        lo, hi = face_range
        Plan.dice(die_kind: :custom, faces: (lo..hi).to_a, count: count, label: "d[#{lo}..#{hi}]")
      elsif (n = @ss.scan(/\d+/))
        faces = n.to_i
        raise ParseError, "die must have at least 1 face" if faces < 1

        Plan.dice(die_kind: :standard, faces: faces, count: count, label: "d#{n}")
      else
        raise ParseError, "invalid die type at #{@ss.rest.inspect}"
      end
    end

    def face_set
      values = []
      loop do
        v = @ss.scan(/-?\d+/) || raise(ParseError, "expected a face value at #{@ss.rest.inspect}")
        values << v.to_i
        break unless @ss.scan(/,/)
      end
      @ss.scan(/\}/) || raise(ParseError, "expected '}' at #{@ss.rest.inspect}")
      values
    end

    def face_range
      lo = @ss.scan(/-?\d+/) || raise(ParseError, "expected range start at #{@ss.rest.inspect}")
      @ss.scan(/\.\./) || raise(ParseError, "expected '..' at #{@ss.rest.inspect}")
      hi = @ss.scan(/-?\d+/) || raise(ParseError, "expected range end at #{@ss.rest.inspect}")
      @ss.scan(/\]/) || raise(ParseError, "expected ']' at #{@ss.rest.inspect}")
      lo = lo.to_i
      hi = hi.to_i
      raise ParseError, "range start #{lo} > end #{hi}" if lo > hi

      [lo, hi]
    end
  end
end
