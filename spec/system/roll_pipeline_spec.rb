# frozen_string_literal: true

require "rails_helper"

RSpec.describe "roll pipeline", type: :system do
  it "rolls a notation end-to-end (parse + cache + evaluate) in the browser" do
    visit "/"
    result = page.evaluate_async_script(<<~JS)
      const done = arguments[0];
      (async () => {
        const m = await import("roll_pipeline");
        const { result } = await m.rollNotation("3d6");
        done(result);
      })();
    JS

    expect(result["kind"]).to eq("sum")
    expect(result["total"]).to be_between(3, 18)
    expect(result["dice"].length).to eq(3)
    expect(result["dice"].map { |d| d["value"] }).to all(be_between(1, 6))
  end

  it "re-rolls a cached notation without a second /parse" do
    visit "/"
    count = page.evaluate_async_script(<<~JS)
      const done = arguments[0];
      (async () => {
        let parses = 0;
        const orig = window.fetch;
        window.fetch = (...a) => { if (String(a[0]).includes("/parse")) parses++; return orig(...a); };
        const m = await import("roll_pipeline");
        await m.rollNotation("2d20kh+5");
        await m.rollNotation("2d20kh+5");
        done(parses);
      })();
    JS
    expect(count).to eq(1)
  end
end
