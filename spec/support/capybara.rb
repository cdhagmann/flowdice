# frozen_string_literal: true

require "capybara/cuprite"

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [400, 900],
    headless: true,
    browser_path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  )
end
Capybara.default_max_wait_time = 5

RSpec.configure do |config|
  config.before(:each, type: :system) { driven_by :cuprite }
end
