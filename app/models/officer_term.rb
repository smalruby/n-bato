# 役員の任期 1 回分。任期が満了しても後任が選ばれるまでは職務を続ける(定款の伸長規定)。
class OfficerTerm < ApplicationRecord
  ROLES = {"chair" => "理事長", "vice_chair" => "副理事長", "director" => "理事", "auditor" => "監事"}.freeze
  # 名簿の「役名」。理事長・副理事長は理事の中から選ぶ。
  TITLES = {"chair" => "理事（理事長）", "vice_chair" => "理事（副理事長）", "director" => "理事", "auditor" => "監事"}.freeze
  TERM_YEARS = 2

  belongs_to :person
  has_many :registrations, dependent: :nullify

  after_create :schedule_registration, if: :representative?
  validates :role, inclusion: {in: ROLES.keys}
  validates :starts_on, :ends_on, presence: true
  validate { errors.add(:ends_on, "は就任日より後にしてください") if starts_on && ends_on && ends_on < starts_on }

  scope :chronological, -> { order(:starts_on, :id) }

  def role_label = ROLES[role]
  def title = TITLES[role]
  def director? = role != "auditor"

  # 任期満了後に次の選任(誰かの新しい任期の始まり)があった日。それまでは伸長規定で職務を続ける。
  def next_election_on
    OfficerTerm.where("starts_on > ?", ends_on).minimum(:starts_on)
  end

  def expired_on?(date) = date > ends_on

  # 職務を行う最後の日
  def last_day
    candidates = [left_on]
    candidates << (next_election_on&.yesterday || Date::Infinity.new) if left_on.nil?
    candidates.compact.min { |a, b| a <=> b }
  end

  # この日に職務を行っているか
  def serving_on?(date) = date.between?(starts_on, last_day)

  # 年度の中で職務を行った期間(名簿の「就任期間」)
  def period_in(fiscal_year)
    from = [starts_on, fiscal_year.starts_on].max
    to = last_day.is_a?(Date) ? [fiscal_year.ends_on, last_day].min : fiscal_year.ends_on
    (from <= to) ? from..to : nil
  end

  def holdover_on?(date) = serving_on?(date) && expired_on?(date)

  def self.serving_on(date) = includes(:person).chronological.select { it.serving_on?(date) }
  def self.serving_in(fiscal_year) = includes(:person).chronological.select { it.period_in(fiscal_year) }

  # 代表権があるか(定款。data/organization.yml の settings.representative_roles で変えられる)
  def representative?
    roles = (Organization.current.settings || {})["representative_roles"].presence || %w[chair vice_chair]
    roles.include?(role)
  end

  private

  def schedule_registration
    registrations.create!(kind: "representative_change", cause_on: starts_on, due_on: starts_on + Registration::DEADLINE_DAYS,
      note: "#{person.name}（#{role_label}）の就任・重任")
  end
end
