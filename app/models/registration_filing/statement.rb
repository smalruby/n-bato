# 登記の申請書に書く文(登記の事由・登記すべき事項・添付書類)を、Nばとの記録から作る。docs/adr/0031
# 書き方は法務局の記載例に合わせる(出典):
# - 特定非営利活動法人(役員変更、全員重任) https://houmukyoku.moj.go.jp/homu/content/001386707.pdf
# - 特定非営利活動法人(役員変更、住所移転) https://houmukyoku.moj.go.jp/homu/content/001252906.pdf
# - 役員の氏名変更(旧氏の併記) https://houmukyoku.moj.go.jp/homu/content/001252648.pdf ・ 001252649.pdf
# 定款で理事長・副理事長だけが代表する法人は、その人だけを資格「理事」で登記する(001386707 の注)。
# 法務局の相談で別の書き方を言われたら、ここを直してテストで固める。
class RegistrationFiling::Statement
  def initialize(filing)
    @filing = filing
    @registrations = filing.registrations.to_a
  end

  # 書いた住所・氏名をいつの値にするか(申請に入れた事由のうち、いちばん新しい日)
  def as_of = @registrations.map(&:cause_on).max || Date.current

  def reason
    words = []
    words << "理事の変更" if kinds.include?("representative_change")
    words << "理事の住所変更" if kinds.include?("address_change")
    if kinds.include?("name_change")
      words << @registrations.select { it.kind == "name_change" }.map { "理事の#{it.person_name_change.change_word}" }.uniq
    end
    words.flatten.join("、")
  end

  # 登記すべき事項(申請用総合ソフトの欄に貼る文)
  def matters
    by_person.map do |person, regs|
      [ "「役員に関する事項」", "「資格」理事", "「住所」#{person.address_on(as_of).presence || '【住所が空】'}",
        "「氏名」#{person.display_name_on(as_of)}", *regs.sort_by { [ it.cause_on, it.id ] }.map(&:cause_line) ].join("\n")
    end.join("\n")
  end

  def attachments
    list = []
    if kinds.include?("representative_change")
      list << "社員総会議事録　１通"
      list << "理事の互選書（又は理事会議事録）　１通"
      list << "定款　１通"
      list << "就任承諾書は、社員総会議事録の記載を援用する。"
    end
    list << "（住所・氏名の変更は、本人が申請するので添付書類はありません。旧氏を併記するときは戸籍の証明書など）" if (kinds & %w[address_change name_change]).any?
    list
  end

  # 人が確かめること(推測で埋めなかったところ)
  def warnings
    list = []
    @registrations.reject(&:cause_day_known?).each do |r|
      list << "#{r.person&.name}の#{r.kind_label}: 日が分かりません(#{r.change.date_label})。住民票(除票を含む)で確かめてから申請してください。"
    end
    @registrations.select { it.kind == "name_change" && it.person_name_change.change_word == "氏名変更" }.each do |r|
      list << "#{r.person&.name}: 氏と名を空白で区切っていないので、「氏変更」「名変更」を決められませんでした。"
    end
    by_person.each { |p, _| list << "#{p.name}: 住所が空です。" if p.address_on(as_of).blank? }
    @registrations.select { it.kind == "representative_change" && !it.reappointment? && it.officer_term }.each do |r|
      earlier = r.officer_term.person.officer_terms.any? { it.starts_on < r.officer_term.starts_on }
      list << "#{r.person.name}: 前の任期が Nばとに記録されていないので「就任」にしました。再任なら「重任」です(前の任期を入れてください)。" unless earlier
    end
    list << "登記の事由が 2 種類以上あります。1 件の申請にまとめられるかを法務局に確かめてください。" if kinds.size > 1
    list
  end

  private

  def kinds = @registrations.map(&:kind).uniq

  def by_person
    order = %w[chair vice_chair director auditor]
    @registrations.group_by(&:person).compact.sort_by { |p, regs| [ regs.map { order.index(it.officer_term&.role) || 9 }.min, p.id ] }
  end
end
