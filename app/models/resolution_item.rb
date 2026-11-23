# 決議の議案 1 つ。役員の選任や事業報告の承認は、成立後に記録へ反映できる。
class ResolutionItem < ApplicationRecord
  KINDS = { "general" => "一般", "officer_election" => "役員の選任", "annual_report_approval" => "事業報告・決算の承認",
            "officer_mutual_election" => "理事長・副理事長の互選" }.freeze

  belongs_to :resolution
  validates :kind, inclusion: { in: KINDS.keys }
  validates :title, presence: true
  validate { errors.add(:base, "「#{@unknown_names.join('、')}」が読めません（登録済みの氏名と、役（理事・監事・理事長・副理事長）を空白で区切って書く）") if @unknown_names.present? }

  def kind_label = KINDS[kind]

  # payload の例
  #   officer_election / officer_mutual_election: { "appointments" => [ { "person_id" => 1, "role" => "director" } ] }
  #   annual_report_approval: { "fiscal_year" => 2024 }
  def appointments = Array((payload || {})["appointments"]).grep(Hash)
  def fiscal_year = (payload || {})["fiscal_year"]

  ROLE_WORDS = { "理事長" => "chair", "副理事長" => "vice_chair", "理事" => "director", "監事" => "auditor" }.freeze

  # 画面では「氏名 役」を 1 行ずつ書く(例: 山田　太郎 理事)
  def appointments_text
    return @appointments_text if @appointments_text

    appointments.map { "#{Person.find_by(id: it['person_id'])&.name} #{OfficerTerm::ROLES[it['role']]}" }.join("\n")
  end

  def appointments_text=(text)
    @appointments_text = text
    @unknown_names = []
    list = text.to_s.lines.map(&:strip).compact_blank.filter_map do |line|
      name, _, word = line.rpartition(/[[:space:]]+/)
      person = Person.find_by(name: name.strip)
      next @unknown_names << name unless person && ROLE_WORDS.key?(word)

      { "person_id" => person.id, "role" => ROLE_WORDS.fetch(word) }
    end
    self.payload = (payload || {}).merge("appointments" => list)
  end

  def fiscal_year=(year)
    self.payload = (payload || {}).merge("fiscal_year" => year.presence&.to_i)
  end

  def applicable? = resolution.established? && applied_on.nil? && kind != "general"

  # 成立した決議の内容を記録に反映する
  def apply!
    raise "決議が成立していません" unless resolution.established?

    date = resolution.established_on
    transaction do
      case kind
      when "officer_mutual_election"
        # 理事として選任済みの任期の役名を、理事長・副理事長に変える(就任は互選の日)
        appointments.each do |a|
          term = OfficerTerm.where(person_id: a.fetch("person_id"), role: "director").order(:starts_on).last or
            raise ActiveRecord::RecordNotFound, "互選の対象の理事の任期がありません"
          term.update!(role: a.fetch("role"))
          term.registrations.create!(kind: "representative_change", cause_on: date, due_on: date + Registration::DEADLINE_DAYS,
                                     note: "#{term.person.name}（#{term.role_label}）の就任・重任") if term.representative?
        end
      when "officer_election"
        appointments.each do |a|
          OfficerTerm.create!(person_id: a.fetch("person_id"), role: a.fetch("role"), starts_on: date,
                              ends_on: date.advance(years: OfficerTerm::TERM_YEARS).yesterday,
                              appointed_by: "#{resolution.body_label}「#{resolution.title}」（#{date}）")
        end
      when "annual_report_approval"
        AnnualReport.find_by!(fiscal_year: fiscal_year).update!(approved_on: date)
      end
      update!(applied_on: Date.current)
    end
  end
end
