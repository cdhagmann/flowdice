# frozen_string_literal: true

require "capybara/cuprite"

# Use the macOS Chrome app path when present (it isn't on PATH there); otherwise
# let ferrum auto-detect Chrome/Chromium (Linux/CI work out of the box).
CHROME_PATH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

Capybara.register_driver(:cuprite) do |app|
  options = { window_size: [400, 900], headless: true }
  options[:browser_path] = CHROME_PATH if File.exist?(CHROME_PATH)
  Capybara::Cuprite::Driver.new(app, **options)
end
Capybara.default_max_wait_time = 5

RSpec.configure do |config|
  config.before(:each, type: :system) { driven_by :cuprite }
end
