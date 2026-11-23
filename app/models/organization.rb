# 法人の基本情報(1 件だけ持つ)。
class Organization < ApplicationRecord
  include YearRecords
  year_records :organization_years, %i[name name_en address representative_title representative_name phone competent_authority accounting_standard_note]
  DEFAULT_ACCOUNTING_STANDARD_NOTE = "財務諸表の作成は、ＮＰＯ法人会計基準（2010年７月20日　2011年11月20日一部改正　ＮＰＯ法人会計基準協議会）によっています。".freeze

  validates :name, presence: true

  # 会員の種別(定款)。data/organization.yml の membership_kinds で上書きできる。
  DEFAULT_MEMBERSHIP_KINDS = [
    { "key" => "regular", "label" => "正会員", "description" => "この法人の目的に賛同して入会し、この法人の活動及び事業を推進する個人", "fee" => "" },
    { "key" => "active", "label" => "活動会員", "description" => "この法人の目的に賛同して入会し、この法人の活動に参加する個人", "fee" => "" },
    { "key" => "student", "label" => "受講会員", "description" => "この法人の目的に賛同して入会し、この法人が運営する教室を受講する個人", "fee" => "" },
    { "key" => "supporting", "label" => "賛助会員", "description" => "この法人の目的に賛同して入会し、この法人の活動を援助する個人及び団体", "fee" => "" }
  ].freeze

  def membership_kinds = (settings || {})["membership_kinds"].presence || DEFAULT_MEMBERSHIP_KINDS

  def self.current = first || new(name: "（法人名未設定）", first_fiscal_year: FiscalYear.current.year)

  def accounting_standard_text = accounting_standard_note.presence || DEFAULT_ACCOUNTING_STANDARD_NOTE
  def period_number(fiscal_year) = first_fiscal_year ? fiscal_year.year - first_fiscal_year + 1 : nil
  def representative = [ representative_title, representative_name ].compact_blank.join("　")
end
