# AI に送る前に、個人情報を伏せる(デザインシステム「やること」の RequestThread、見直し第9回)。
# 伏せるもの: n-bato に登録されている人の住所・メール・電話(そのまま一致)、メールアドレス、電話番号、郵便番号、住所らしい文字列。
# 氏名・役職・日付・年度は残す(やることを決めるのに要るため)。伏せた箇所は【伏せた住所】のように置き換える。
class Masker
  LABELS = { address: "住所", email: "メールアドレス", phone: "電話番号", postal: "郵便番号" }.freeze
  PREFS = "北海道|東京都|京都府|大阪府|(?:青森|岩手|宮城|秋田|山形|福島|茨城|栃木|群馬|埼玉|千葉|神奈川|新潟|富山|石川|福井|山梨|長野|岐阜|静岡|愛知|三重|滋賀|兵庫|奈良|和歌山|鳥取|島根|岡山|広島|山口|徳島|香川|愛媛|高知|福岡|佐賀|長崎|熊本|大分|宮崎|鹿児島|沖縄)県"
  PATTERNS = [
    [ :email, /[\w.+-]+@[\w-]+(?:\.[\w-]+)+/ ],
    [ :postal, /〒?\s?[0-9０-９]{3}[-－ー−‐][0-9０-９]{4}(?![0-9０-９])/ ],
    [ :phone, /(?<![0-9０-９])0[0-9０-９]{1,4}[-－ー−‐(（]?[0-9０-９]{1,4}[-－ー−‐)）]?[0-9０-９]{3,4}(?![0-9０-９])/ ],
    # 都道府県か「〜市・〜郡」で始まり、番地の数字で終わるもの
    [ :address, /(?:(?:#{PREFS})\s?)?[一-龥ぁ-んァ-ヶー]{1,8}[市郡区][一-龥ぁ-んァ-ヶー]{0,12}?(?:[町村]|区)?[一-龥ぁ-んァ-ヶー0-9０-９]*?[0-9０-９]+(?:\s?[-－ー−‐の丁目番地号]\s?[0-9０-９]*)*(?:[\s　]*[^\s　、。,]{0,20}?(?:[0-9０-９]+号室?|[0-9０-９]+[FＦ]))?/ ]
  ].freeze

  Result = Data.define(:text, :counts) do
    def masked? = counts.values.sum.positive?
    def summary = counts.select { _2.positive? }.map { |k, n| "#{LABELS[k]} #{n} か所" }.join("・")
  end

  def initialize(known: self.class.known_values)
    @known = known.sort_by { -it[1].length }
  end

  def mask(text)
    counts = Hash.new(0)
    out = text.to_s.dup
    @known.each do |kind, value|
      next if value.blank? || value.length < 4

      n = out.scan(value).size
      next if n.zero?

      out = out.gsub(value, mark(kind))
      counts[kind] += n
    end
    PATTERNS.each do |kind, re|
      out = out.gsub(re) do |m|
        next m if m.start_with?("【")

        counts[kind] += 1
        mark(kind)
      end
    end
    Result.new(out, LABELS.keys.index_with { counts[it] })
  end

  def mark(kind) = "【伏せた#{LABELS.fetch(kind)}】"

  # n-bato に登録されている人と法人以外の住所・メール・電話(年度ごとの記録・住所の移り変わり・入会申込も)
  def self.known_values
    people = Person.includes(:address_changes, :name_changes).to_a
    addresses = people.flat_map { [ it.address_at_start, *it.address_changes.map(&:address) ] }
    contacts = (people + PersonYear.all.to_a + MemberApplication.all.to_a).flat_map { |r| [ [ :email, r.email ], [ :phone, r.phone ] ] }
    (addresses.map { [ :address, it ] } + MemberApplication.all.map { [ :address, it.address ] } + contacts).reject { it[1].blank? }.uniq
  end
end
