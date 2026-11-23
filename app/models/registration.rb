# 登記の事由(長いイベント: 事由が起きてから登記するまで)。docs/adr/0031
# 代表権のある理事(定款で決める。既定は理事長・副理事長)の就任・重任、住所の変更、氏名の変更は、2 週間以内に変更登記する。
# どの申請(RegistrationFiling)に入れたかと、登記した日(いまの状態。申請の完了で決まる)を持つ。
class Registration < ApplicationRecord
  KINDS = { "representative_change" => "理事の変更（重任・就任）", "address_change" => "理事の住所の変更",
            "name_change" => "理事の氏名の変更", "other" => "その他の登記" }.freeze
  DEADLINE_DAYS = 14

  belongs_to :officer_term, optional: true
  belongs_to :person_address_change, class_name: "Person::AddressChange", optional: true
  belongs_to :person_name_change, class_name: "Person::NameChange", optional: true
  belongs_to :registration_filing, optional: true

  validates :kind, inclusion: { in: KINDS.keys }
  validates :cause_on, presence: true

  scope :pending, -> { where(registered_on: nil) }
  scope :chronological, -> { order(:cause_on, :id) }

  def kind_label = KINDS[kind]
  def done? = registered_on.present?
  def overdue?(today = Date.current) = !done? && due_on.present? && due_on < today
  def change = person_address_change || person_name_change
  def person = officer_term&.person || change&.person

  # 申請に入れられるか(まだ登記しておらず、進行中の申請に入っていない)
  def available? = !done? && (registration_filing.nil? || registration_filing.withdrawn?)

  # 原因の日が日まで分かっているか(住所・氏名の出来事は日が不明のことがある)
  def cause_day_known? = change.nil? || change.day_known?

  # 重任か就任か: 同じ人の代表権のある任期が、すき間なく続いていれば重任
  def reappointment?
    return false unless officer_term

    officer_term.person.officer_terms.any? do |t|
      next false if t == officer_term || !t.representative? || t.starts_on >= officer_term.starts_on

      last = t.last_day
      !last.is_a?(Date) || last >= officer_term.starts_on - 1
    end
  end

  # 登記すべき事項の「原因年月日」の行(日が不明なら、その旨を入れて推測で埋めない)
  def cause_line
    date = cause_day_known? ? Wareki.date(cause_on) : "【日が不明: #{change.date_label}。住民票で確かめる】"
    case kind
    when "representative_change" then "「原因年月日」#{date}#{reappointment? ? '重任' : '就任'}"
    when "address_change" then "「原因年月日」#{date}住所移転"
    when "name_change" then "「原因年月日」#{date}#{person_name_change.former_name}の#{person_name_change.change_word}"
    else "「原因年月日」#{date}#{note}"
    end
  end
end
