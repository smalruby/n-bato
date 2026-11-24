# 決議の議案 1 つ(決議の中身。成立前は自由に直してよい)。役員の選任や事業報告の承認は、成立後に記録へ反映できる。
# 反映は詳細のイベント ResolutionItem::Application(docs/adr/0038)。
class ResolutionItem < ApplicationRecord
  KINDS = {"general" => "一般", "officer_election" => "役員の選任", "annual_report_approval" => "事業報告・決算の承認",
           "officer_mutual_election" => "理事長・副理事長の互選"}.freeze

  belongs_to :resolution
  has_one :application, class_name: "ResolutionItem::Application", dependent: :restrict_with_error
  validates :kind, inclusion: {in: KINDS.keys}
  validates :title, presence: true
  validate { errors.add(:base, "「#{@unknown_names.join("、")}」が読めません（登録済みの氏名と、役（理事・監事・理事長・副理事長）を空白で区切って書く）") if @unknown_names.present? }

  def kind_label = KINDS[kind]

  # payload の例
  #   officer_election / officer_mutual_election: { "appointments" => [ { "person_id" => 1, "role" => "director" } ] }
  #   annual_report_approval: { "fiscal_year" => 2024 }
  def appointments = Array((payload || {})["appointments"]).grep(Hash)
  def fiscal_year = (payload || {})["fiscal_year"]

  ROLE_WORDS = {"理事長" => "chair", "副理事長" => "vice_chair", "理事" => "director", "監事" => "auditor"}.freeze

  # 画面では「氏名 役」を 1 行ずつ書く(例: 山田　太郎 理事)
  def appointments_text
    return @appointments_text if @appointments_text

    appointments.map { "#{Person.find_by(id: it["person_id"])&.name} #{OfficerTerm::ROLES[it["role"]]}" }.join("\n")
  end

  def appointments_text=(text)
    @appointments_text = text
    @unknown_names = []
    list = text.to_s.lines.map(&:strip).compact_blank.filter_map do |line|
      name, _, word = line.rpartition(/[[:space:]]+/)
      person = Person.find_by_current_name(name)
      next @unknown_names << name unless person && ROLE_WORDS.key?(word)

      {"person_id" => person.id, "role" => ROLE_WORDS.fetch(word)}
    end
    self.payload = (payload || {}).merge("appointments" => list)
  end

  def fiscal_year=(year)
    self.payload = (payload || {}).merge("fiscal_year" => year.presence&.to_i)
  end

  scope :applied, -> { where(id: ResolutionItem::Application.select(:resolution_item_id)) }
  scope :unapplied, -> { where.not(id: ResolutionItem::Application.select(:resolution_item_id)) }

  def applied? = application.present?
  # 記録に反映した日(ResolutionItem::Application。移す前は列だった)
  def applied_on = application&.applied_on

  def applicable? = resolution.established? && !applied? && kind != "general"
end
