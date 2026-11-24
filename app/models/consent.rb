# 書面決議への同意(書面または電子メール)。イベント(日付は consented_on。docs/adr/0038)。
# 「取り消す」は消さずに Consent::Cancellation を足す。決議の成立に数えるのは、取り消していない同意だけ(Consent.active)。
# 取り消したあとは、同じ人の同意をもう一度記録できる(取り消していない同意は 1 人 1 つ)。
class Consent < ApplicationRecord
  include EventRecord

  event_of :consented_on, entry: :record!

  VIAS = {"paper" => "書面", "email" => "電子メール"}.freeze
  belongs_to :resolution
  belongs_to :person
  has_one :cancellation, class_name: "Consent::Cancellation", dependent: :restrict_with_error

  validates :consented_on, presence: true
  validates :via, inclusion: {in: VIAS.keys}
  validate :one_active_consent_per_person, on: :create

  scope :active, -> { where.not(id: Consent::Cancellation.select(:consent_id)) }

  def self.model_name_label = "同意"
  # 元に戻す・やり直すのあとに、決議を確かめる(取り消していない同意の重なり・反映した議案のある決議が成立しているか)
  def self.audit_state_owner(change) = Resolution.find_by(id: change.value("resolution_id"))

  def via_label = VIAS[via]
  def cancelled? = cancellation.present?

  # 取り消せないときの理由(BlockedReason)。取り消せるなら nil。決議の画面の「取り消す」と Consent::Cancellation.cancel! で使う。
  def cancel_blocked_reason
    return BlockedReason.new(title: "この同意は取り消せません", reason: "もう取り消してあります。") if cancelled?
    return unless (applied = resolution.items.count(&:applied?)).positive?

    BlockedReason.new(title: "この同意は取り消せません",
                      reason: "取り消すと決議が成立しなくなり、反映した記録と食い違うので、記録に反映した議案のある決議の同意は取り消せません。",
                      what: "記録に反映した議案が #{applied} 件あります", link_label: "議案を見る", link_target: "#items")
  end

  # 同意を記録する。書けなければ ActiveRecord::RecordInvalid(もう同意を記録してある・日付が無いなど)。
  def self.record!(resolution, person:, consented_on:, via: "paper", note: "")
    Audit.operation do
      transaction(requires_new: true) do
        create!(resolution:, person:, consented_on:, via:, note: note.to_s)
      end
    end
  end

  private

  def one_active_consent_per_person
    return unless resolution && person
    return unless Consent.active.where(resolution_id:, person_id:).exists?

    errors.add(:base, "#{person.name} さんの同意は、もう記録してあります")
  end
end
