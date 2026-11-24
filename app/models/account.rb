class Account < ApplicationRecord
  include YearlyDataset

  # NPO 法人会計基準の区分。会計王の科目性格コードで決める。
  CATEGORIES = {
    "asset" => "資産", "liability" => "負債", "net_assets" => "正味財産",
    "revenue" => "経常収益", "program_expense" => "事業費", "admin_expense" => "管理費",
    "extraordinary" => "経常外損益", "tax" => "法人税等", "special" => "特別・非財務"
  }.freeze
  BALANCE_SHEET = %w[asset liability net_assets].freeze
  ACTIVITY = %w[revenue program_expense admin_expense extraordinary].freeze

  has_many :opening_balances, dependent: :restrict_with_error

  validates :code, presence: true
  validates :name, presence: true
  validates :category, inclusion: {in: CATEGORIES.keys}

  before_validation do
    if code
      self.nature_code ||= self.class.default_nature_code(code)
      self.category = self.class.category_for_nature(nature_code) if category.blank? || will_save_change_to_nature_code?
    end
  end

  scope :ordered, -> { order(:code) }

  # 会計王の「科目性格コード」(勘定科目設定の書き出しにある)で区分を決める。
  # 1xxxx 貸借対照表(111xx 流動資産・112xx 固定資産・113xx 繰延資産・121xx 流動負債・122xx 固定負債・13xxx 正味財産)
  # 21110 経常収益 / 2112x〜2117x 事業費(21121 人件費)/ 2118x 管理費(21181 人件費)
  # 221xx・222xx 経常外収益 / 223xx〜225xx 経常外費用 / 23000 法人税等 / 4xxxx・5xxxx 特別・非財務
  def self.category_for_nature(nature)
    case nature
    when 11000...12000 then "asset"
    when 12000...13000 then "liability"
    when 13000...14000 then "net_assets"
    when 21110 then "revenue"
    when 21120...21180 then "program_expense"
    when 21180...21200 then "admin_expense"
    when 22000...23000 then "extraordinary"
    when 23000 then "tax"
    when 23001...24000 then "net_assets"
    else "special"
    end
  end

  # 勘定科目設定を取り込む前(SIWAKE だけ取り込んだとき)に使う、会計王の NPO 法人向け標準の科目コードの範囲。
  # 2026-11-20 に会計王の勘定科目設定の書き出しで確かめた。
  DEFAULT_NATURES = [
    [100..199, 11150], [200..299, 11210], [300..369, 12110], [370..399, 12200],
    [500..599, 21110], [600..619, 21121], [620..699, 21122], [700..719, 21181], [720..799, 21182],
    [950..959, 22100], [960..979, 22300], [980..980, 23000], [981..988, 23002]
  ].freeze

  def self.default_nature_code(code)
    DEFAULT_NATURES.find { |range, _| range.cover?(code) }&.last || 40001
  end

  # 活動計算書の小区分(勘定科目設定が無いときの受取収益の区分)
  REVENUE_GROUPS = [
    [500..509, "受取会費"], [510..519, "受取寄付金"], [520..529, "受取助成金等"],
    [530..549, "事業収益"], [550..599, "その他収益"]
  ].freeze
  PERSONNEL_NATURES = [21121, 21181].freeze

  def activity_group
    case category
    when "revenue"
      group_name.presence || REVENUE_GROUPS.find { |range, _| range.cover?(code) }&.last || "その他収益"
    when "program_expense", "admin_expense" then personnel? ? "人件費" : "その他経費"
    when "extraordinary" then (nature_code < 22300) ? "経常外収益" : "経常外費用"
    end
  end

  def personnel? = PERSONNEL_NATURES.include?(nature_code)
  def current_asset? = category == "asset" && nature_code < 11200
  def current_liability? = category == "liability" && nature_code < 12200

  # 会計王の科目名は桁合わせの空白を含む("現      金")。表示用には取り除く。
  def self.display_name_for(name) = name.to_s.gsub(/[[:space:]]/, "")

  def display_name = self.class.display_name_for(name)
  def category_label = CATEGORIES[category]
  def balance_sheet? = BALANCE_SHEET.include?(category)
  def activity? = ACTIVITY.include?(category)
  def expense? = %w[program_expense admin_expense].include?(category)

  # 借方がプラスになる区分か(資産・費用)。
  def debit_normal? = %w[asset program_expense admin_expense].include?(category)

  def to_s = "#{code} #{display_name}"
end
