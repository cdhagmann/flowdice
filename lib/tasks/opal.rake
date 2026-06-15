# frozen_string_literal: true

require_relative "../flow_dice_opal"

namespace :opal do
  desc "Compile the FlowDice evaluator to vendor/javascript/flow_dice_evaluator.js"
  task build: :environment do
    js = FlowDiceOpal.build
    path = Rails.root.join("vendor/javascript/flow_dice_evaluator.js")
    File.write(path, js)
    puts "wrote #{path} (#{js.bytesize} bytes)"
  end
end
