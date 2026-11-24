require "test_helper"

class PdfRendererTest < ActiveSupport::TestCase
  test "自動テストでは Chrome を立ち上げず、偽物で PDF を作る" do
    assert_equal PdfRenderer::Fake, PdfRenderer.engine
    pdf = PdfRenderer.render("<h1>見本</h1>")
    assert pdf.start_with?("%PDF")
    assert_equal "<h1>見本</h1>", PdfRenderer::Fake.last_html
  end

  test "作り方を決めていなければ Chrome で作る" do
    original = PdfRenderer.engine
    PdfRenderer.engine = nil
    assert_equal PdfRenderer::Chrome, PdfRenderer.engine
  ensure
    PdfRenderer.engine = original
  end

  # Ferrum::Browser の偽物。頼まれたことを覚える(本物の Chrome は立ち上げない)
  class FakeBrowser
    class << self
      attr_accessor :last, :fail_on_page
    end

    attr_reader :options, :page, :quitted

    def initialize(**options)
      @options = options
      self.class.last = self
    end

    def create_page
      raise "タブを作れない(試し)" if self.class.fail_on_page

      @page = FakePage.new
    end

    def quit = @quitted = true
  end

  class FakePage
    attr_accessor :content
    attr_reader :pdf_options

    def network = self
    def wait_for_idle(timeout:) = raise("待ちきれない(試し)") # 待ちきれなくても PDF は作る
    def pdf(**options) = (@pdf_options = options) && "%PDF-fake"
  end

  def with_fake_browser
    PdfRenderer::Chrome.browser_class = FakeBrowser
    yield
  ensure
    PdfRenderer::Chrome.browser_class = nil
    FakeBrowser.last = FakeBrowser.fail_on_page = nil
  end

  test "Chrome で作るときは、待つ秒数をそろえ、A4 の PDF にして、Chrome を閉じる" do
    assert_equal Ferrum::Browser, PdfRenderer::Chrome.browser_class
    with_fake_browser do
      assert_equal "%PDF-fake", PdfRenderer::Chrome.render("<p>見本</p>")
      browser = FakeBrowser.last
      assert_equal [ true, 60, 60, 60 ], browser.options.values_at(:headless, :timeout, :process_timeout, :protocol_timeout)
      assert_equal "<p>見本</p>", browser.page.content
      assert_equal :A4, browser.page.pdf_options[:format]
      assert browser.quitted
    end
  end

  test "Chrome で作るのに失敗しても、Chrome を閉じる" do
    with_fake_browser do
      FakeBrowser.fail_on_page = true
      assert_raises(RuntimeError) { PdfRenderer::Chrome.render("<p>見本</p>") }
      assert FakeBrowser.last.quitted
    end
  end
end
