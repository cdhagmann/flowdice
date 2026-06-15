# frozen_string_literal: true

module FlowDice
  # Deterministic RNG for tests. Returns queued values in order and asserts
  # each is within the requested [min, max] range.
  class SequenceRng
    def initialize(values)
      @values = values.dup
    end

    def int(min, max)
      raise "SequenceRng exhausted" if @values.empty?

      v = @values.shift
      unless (min..max).cover?(v)
        raise "SequenceRng value #{v} out of range [#{min}, #{max}]"
      end
      v
    end
  end
end
