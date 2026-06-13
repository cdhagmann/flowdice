# frozen_string_literal: true

module FlowDice
  # Builder functions for plan tree nodes. Nodes are plain symbol-keyed hashes
  # so they are Opal-safe and trivially JSON-serializable.
  module Plan
    module_function

    def dice(die_kind:, faces:, count:, label:, keep: nil)
      { type: :dice, die_kind: die_kind, faces: faces, count: count, keep: keep, label: label }
    end

    def const(value)
      { type: :const, value: value }
    end

    def binary(op, left, right)
      { type: :binary, op: op, left: left, right: right }
    end

    def crit(mode, child)
      { type: :crit, mode: mode, child: child }
    end
  end
end
