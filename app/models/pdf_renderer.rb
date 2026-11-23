# HTML を A4 の PDF にする(ヘッドレス Chrome)。
class PdfRenderer
  def self.render(html)
    browser = Ferrum::Browser.new(headless: true, timeout: 30, browser_options: { "no-sandbox" => nil })
    page = browser.create_page
    page.content = html
    page.network.wait_for_idle(timeout: 5) rescue nil
    page.pdf(format: :A4, encoding: :binary, print_background: true, prefer_css_page_size: true)
  ensure
    browser&.quit
  end
end
