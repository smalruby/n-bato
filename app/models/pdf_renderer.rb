# HTML を A4 の PDF にする(ヘッドレス Chrome)。
class PdfRenderer
  # 待つ秒数。Ferrum の既定は、Chrome の立ち上がり(process_timeout)が 10 秒、タブを作るなどの内部の命令
  # (protocol_timeout)が 5 秒で、`timeout:` を大きくしても後の 2 つは変わらない。
  # 負荷が高いと立ち上がりに 10 秒を超え、ProcessTimeoutError や Target.createTarget の TimeoutError になる
  # (issue #9: テストを並列で流すとときどき 1 件エラーになった原因。小さいサーバーでも起こりうる)。そろえて 60 秒にする(ふだんは 1 秒ほどで終わる。上限なので、遅いときに待つだけ)。
  TIMEOUT = 60

  def self.render(html)
    browser = Ferrum::Browser.new(headless: true, timeout: TIMEOUT, process_timeout: TIMEOUT, protocol_timeout: TIMEOUT,
                                  browser_options: { "no-sandbox" => nil })
    page = browser.create_page
    page.content = html
    page.network.wait_for_idle(timeout: 5) rescue nil
    page.pdf(format: :A4, encoding: :binary, print_background: true, prefer_css_page_size: true)
  ensure
    browser&.quit
  end
end
