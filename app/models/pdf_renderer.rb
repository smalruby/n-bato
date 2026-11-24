# HTML を A4 の PDF にする。
#
# 作り方(engine)は差し替えられる。本番・開発はヘッドレス Chrome(Chrome)、自動テストは偽物(Fake)で、
# テストでは Chrome を立ち上げない(issue #9: Chrome の立ち上がりが負荷で遅れ、テストがときどき失敗していた)。
# Chrome を Rails の外に出すこと(運用の手間を減らす)は別の Issue で決める。
class PdfRenderer
  class << self
    attr_writer :engine

    def engine = @engine || Chrome

    def render(html) = engine.render(html)
  end

  # ヘッドレス Chrome で作る。
  module Chrome
    # 待つ秒数。Ferrum の既定は、Chrome の立ち上がり(process_timeout)が 10 秒、タブを作るなどの内部の命令
    # (protocol_timeout)が 5 秒で、`timeout:` を大きくしても後の 2 つは変わらない。負荷が高いと立ち上がりに
    # 10 秒を超え、ProcessTimeoutError になる。そろえて 60 秒にする(ふだんは 1 秒ほど。上限なので、遅いときに待つだけ)。
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

  # 自動テスト用。PDF の形だけの中身を返し、渡された HTML を覚えておく(何を PDF にしたかをテストで確かめる)。
  module Fake
    PDF = "%PDF-1.4\n% n-bato test (PdfRenderer::Fake)\n%%EOF\n".b.freeze

    class << self
      attr_reader :rendered

      def render(html)
        (@rendered ||= []) << html
        PDF
      end

      def last_html = rendered&.last

      def reset! = @rendered = []
    end
  end
end
