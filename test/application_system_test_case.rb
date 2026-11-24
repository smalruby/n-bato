require "test_helper"
require "capybara/playwright"
require Rails.root.join("db/demo/seed").to_s

# ブラウザを動かすテスト(issue #14)。bin/rails test:system で流す(bin/rails test には入らない)。
# Playwright の版は .playwright-version(npx で動かす。ブラウザは npx playwright@版 install chromium で入れる)。
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  PLAYWRIGHT_VERSION = Rails.root.join(".playwright-version").read.strip
  # HEADFUL=1 でブラウザの窓を出す
  driven_by :playwright, screen_size: [ 1400, 1000 ], options: {
    browser_type: :chromium, headless: ENV["HEADFUL"].blank?, locale: "ja-JP",
    playwright_cli_executable_path: "npx -y playwright@#{PLAYWRIGHT_VERSION}"
  }

  DEMO_PASSWORD = "demo-system-test".freeze
  # 表のセルの入力欄は aria-label で名前を付けている(例:「受取寄付金の小区分」)
  Capybara.enable_aria_label = true

  # 架空のデータ(bin/demo と同じ種)を入れ、ブラウザの JavaScript のエラーを集める
  setup do
    @demo = Demo.seed!(password: DEMO_PASSWORD)
    @browser_errors = []
    page.driver.with_playwright_page do |pw|
      pw.on("pageerror", ->(err) { @browser_errors << "JavaScript の例外: #{err.message}" })
      pw.on("console", ->(msg) { @browser_errors << "console.error: #{msg.text}" if msg.type == "error" })
    end
  end

  teardown do
    assert_empty @browser_errors, "ブラウザでエラーが出ました"
  end

  private

  # ログインの画面から、メールアドレスとパスワードでログインする(パスキーではなく)
  def sign_in_as_ai
    visit new_session_path
    fill_in "メールアドレス", with: Demo::EMAIL
    fill_in "パスワード", with: DEMO_PASSWORD
    click_on "ログイン"
    assert_selector "nav.nb-nav"
  end

  # ページ全体が横にはみ出していないか(はみ出した幅)
  def horizontal_overflow = evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")
end
