# 定款の全文(Markdown)を、章と条に分ける(デザインシステム Articles、見直し第13回)。
#   ## 第１章　総則      … 章
#   #### （名称）        … 次の条の見出し
#   第１条　この法人は… … 条(次の見出しか章までが、その条の文)
# 「附則」のように条の無い章は、文を paragraphs に入れる。引用(>)と表題(# )は読まない。
module Articles
  class Document
    Article = Data.define(:number, :caption, :paragraphs, :chapter) do
      def label = "第#{number}条"
      def text = paragraphs.join("\n")
      def anchor = "a-#{number}"
    end
    Chapter = Data.define(:title, :articles, :paragraphs) do
      def anchor = "c-#{title[/第([0-9０-９]+)章/, 1]&.tr('０-９', '0-9') || 'x'}"
    end

    def self.number(str) = str.to_s.tr("０-９", "0-9").to_i

    def initialize(body)
      @body = body.to_s
    end

    def chapters = @chapters ||= parse
    def articles = chapters.flat_map(&:articles)
    def article(number) = articles.find { it.number == number.to_i }

    # 見出しで条を探す(章の名前で絞れる)。条の番号は定款ごとに違うので、見出しで引く。
    def find(caption, chapter: nil)
      articles.find { it.caption == caption && (chapter.nil? || it.chapter.to_s.match?(chapter)) }
    end

    # 「要約」に出すもの: [見出し, 条の配列]
    SUMMARY = [
      [ "目的", [ [ "目的" ] ] ],
      [ "事業", [ [ "事業" ] ] ],
      [ "会員と会費", [ [ "種別", /会員/ ], [ "入会金及び会費" ] ] ],
      [ "事業年度", [ [ "事業年度" ] ] ],
      [ "役員", [ [ "種別及び定数" ], [ "任期等" ] ] ],
      [ "総会", [ [ "開催", /総会/ ], [ "議決", /総会/ ] ] ],
      [ "理事会", [ [ "開催", /理事会/ ], [ "議決", /理事会/ ] ] ],
      [ "決算", [ [ "事業報告及び決算" ] ] ]
    ].freeze

    def summary
      SUMMARY.filter_map do |title, keys|
        list = keys.filter_map { |caption, chapter| find(caption, chapter:) }
        [ title, list ] if list.any?
      end
    end

    # 事業の条の「①〜⑨」。[番号, 名前] の配列
    def programs
      Array(find("事業")&.paragraphs).filter_map do |line|
        m = line.sub(/\A[[:space:]]+/, "").match(/\A([①-⑨])(.+)\z/) or next
        [ "①②③④⑤⑥⑦⑧⑨".index(m[1]) + 1, m[2].strip ]
      end
    end

    private

    def parse
      list = []
      caption = nil
      @body.each_line(chomp: true) do |raw|
        line = raw.rstrip
        next if line.start_with?(">") || line.match?(/\A# [^#]/) || line.strip.empty?

        if (m = line.match(/\A##\s+(.+)\z/)) && !line.start_with?("###")
          list << { title: m[1].strip, articles: [], paragraphs: [] }
          caption = nil
        elsif (m = line.match(/\A####\s*(.+)\z/))
          caption = m[1].strip.delete_prefix("（").delete_suffix("）")
        elsif (m = line.match(/\A第([0-9０-９]+)条[　 ]*(.*)\z/))
          list << { title: "", articles: [], paragraphs: [] } if list.empty?
          list.last[:articles] << { number: self.class.number(m[1]), caption:, paragraphs: [ m[2] ] }
          caption = nil
        else
          list << { title: "", articles: [], paragraphs: [] } if list.empty?
          target = list.last[:articles].last
          target ? target[:paragraphs] << line.strip : list.last[:paragraphs] << line.strip
        end
      end
      list.map do |c|
        chapter = Chapter.new(title: c[:title], articles: [], paragraphs: c[:paragraphs])
        chapter.articles.concat(c[:articles].map { Article.new(number: it[:number], caption: it[:caption], paragraphs: it[:paragraphs], chapter: c[:title]) })
        chapter
      end
    end
  end
end
