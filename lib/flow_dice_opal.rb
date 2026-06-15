# frozen_string_literal: true

require "opal"

# Compiles the Opal evaluator entry (runtime + entry) to a JS string. Single
# source of truth for both `rake opal:build` and the freshness spec.
module FlowDiceOpal
  def self.build
    engine_lib = Rails.root.join("packs/dice_engine/lib").to_s

    # Opal.paths freezes @paths on first access (inside builder.build). Guard
    # against calling append_path on an already-frozen array, e.g. when two
    # specs both call build in the same Ruby process. Use the internal @paths
    # to avoid triggering the freeze prematurely.
    opal_internal = Opal.instance_variable_get(:@paths)
    unless opal_internal.include?(engine_lib)
      # If frozen, reset first — reset_paths! thaws @paths so append_path works.
      Opal.reset_paths! if opal_internal.frozen?
      Opal.append_path(engine_lib)
    end

    builder = Opal::Builder.new
    builder.build("opal")
    builder.build("flow_dice/opal/entry")
    builder.to_s
  end
end
