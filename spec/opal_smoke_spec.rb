# frozen_string_literal: true

require "rails_helper"
require "opal"
require "mini_racer"

RSpec.describe "Opal + mini_racer toolchain" do
  it "compiles a Ruby method to JS and runs it in V8 with interop" do
    # Opal 1.8 backtick syntax requires the magic comment to suppress the deprecation
    # warning about backtick_javascript. Nested backticks (e.g. `a`) inside a backtick
    # string are a syntax error in Opal 1.8's parser, so we expose the compiled Ruby
    # module to the JS global scope by referencing `Opal.Smoke` (the compiled constant)
    # from within a backtick JS snippet.
    ruby = <<~RUBY
      # backtick_javascript: true
      module Smoke
        def self.add(a, b)
          a + b
        end
      end
      `globalThis.Smoke = { add: function(a, b) { return Opal.Smoke.$add(a, b); } }`
    RUBY

    builder = Opal::Builder.new
    builder.build("opal")
    builder.build_str(ruby, "smoke_test")
    js = builder.to_s

    ctx = MiniRacer::Context.new
    ctx.eval(js)
    expect(ctx.eval("Smoke.add(40, 2)")).to eq(42)
  end
end
