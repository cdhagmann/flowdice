# frozen_string_literal: true

require "securerandom"

module FlowDice
  # Cryptographically secure RNG. The browser supplies an equivalent backed by
  # crypto.getRandomValues() in the Opal evaluator (increment #3).
  class SecureRandomRng
    # Uniform integer in the inclusive range [min, max].
    def int(min, max)
      raise ArgumentError, "min (#{min}) > max (#{max})" if min > max

      min + SecureRandom.random_number(max - min + 1)
    end
  end
end
