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
  config.before(:each, type: :system) do
    driven_by :cuprite
    # Restart the browser before each system spec to guarantee a clean Chrome
    # process. This prevents a JS-heavy page (e.g. the Opal evaluator) from
    # leaving the DevTools WebSocket in a broken state that kills subsequent
    # specs. The overhead is acceptable (≈0.5 s per spec) given the tiny count.
    Capybara.current_session.driver.browser.restart
  end
end
