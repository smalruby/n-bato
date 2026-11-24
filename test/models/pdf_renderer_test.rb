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
end
