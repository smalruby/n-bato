# 会員・役員になる人。住所・メール・電話は暗号化して保存する。
#
# 氏名・よみ・住所(docs/adr/0029):
# - 列の値は「記録の始まり」(登録したとき)の値。打ち間違いは直してよい(ADR-0006。操作履歴に残る)。
# - 住所が変わった・氏名が変わったは、日付つきの出来事(Person::AddressChange・Person::NameChange)で足す。
# - name・name_kana・address は「いまの値」(取り消していない最後の出来事。無ければ記録の始まり)。
#   ある日の値は name_on(date)・address_on(date)。役員名簿・届出書・登記はこちらを使う。
# メール・電話・メモは年度ごとの記録(person_years)。
class Person < ApplicationRecord
  include YearRecords

  encrypts :address, :email, :phone
  year_records :person_years, %i[email phone notes]

  has_many :memberships, dependent: :destroy
  has_many :officer_terms, dependent: :restrict_with_error
  has_many :address_changes, -> { order(:moved_on, :id) }, class_name: "Person::AddressChange", dependent: :restrict_with_error
  has_many :name_changes, -> { order(:changed_on, :id) }, class_name: "Person::NameChange", dependent: :restrict_with_error

  validates :name, presence: true
  scope :ordered, -> { order(:name_kana, :name) }

  # 記録の始まりの値
  def name_at_start = self[:name]
  def name_kana_at_start = self[:name_kana]
  def address_at_start = self[:address]

  def name = latest_name_change&.name || name_at_start
  def name_kana = latest_name_change&.name_kana || name_kana_at_start
  def address = latest_address_change&.address || address_at_start
  def to_s = name

  # 住所・氏名の出来事があれば、記録の始まりの値は画面からは直さない(出来事で足す)
  def changes_recorded? = active_address_changes.any? || active_name_changes.any?

  def active_address_changes = address_changes.reject(&:cancelled?)
  def active_name_changes = name_changes.reject(&:cancelled?)
  def latest_address_change = active_address_changes.last
  def latest_name_change = active_name_changes.last

  # その日の値(その日までの出来事。日が分からない出来事は、分かっている範囲の初め(月の 1 日・年度の 4/1)で数える)
  def address_on(date) = active_address_changes.select { it.moved_on <= date }.last&.address || address_at_start
  def name_change_on(date) = active_name_changes.select { it.changed_on <= date }.last
  def name_on(date) = name_change_on(date)&.name || name_at_start
  def name_kana_on(date) = name_change_on(date)&.name_kana || name_kana_at_start

  # 名簿・登記に書く氏名(旧氏を併記すると決めたときは「新しい氏名（旧氏 名）」)
  def display_name_on(date)
    change = name_change_on(date)
    change&.show_former_name ? change.name_with_former : name_on(date)
  end

  # 住所・氏名の移り変わり(画面の表)。記録の始まり → 出来事を日付の順に。取り消したものも出す。
  History = Struct.new(:on, :precision, :kind, :address, :name, :change)

  def history
    rows = (address_changes.to_a + name_changes.to_a).sort_by { [it.occurred_on, it.class.name, it.id] }
    cur_address = address_at_start
    cur_name = name_at_start
    [History.new(kind: :start, address: cur_address, name: cur_name)] + rows.map do |c|
      unless c.cancelled?
        cur_address = c.address if c.is_a?(Person::AddressChange)
        cur_name = c.display_name if c.is_a?(Person::NameChange)
      end
      History.new(on: c.occurred_on, precision: c.date_precision, kind: c.is_a?(Person::AddressChange) ? :address : :name,
        address: cur_address, name: cur_name, change: c)
    end
  end

  # いまの氏名で探す(改姓のあとも見つかる)
  def self.find_by_current_name(text)
    text = text.to_s.strip
    return nil if text.empty?

    all.includes(:name_changes).find { it.name == text || it.name.gsub(/[\s　]+/, "") == text.gsub(/[\s　]+/, "") }
  end

  def member_in?(year, kind: "regular") = memberships.any? { it.fiscal_year == year && it.kind == kind }
end
