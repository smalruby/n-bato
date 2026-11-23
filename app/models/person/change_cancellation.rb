# 住所の変更・改姓の取消(イベント。日時は cancelled_at)。打ち間違いのときに取り消して、入れ直す。docs/adr/0029
# 取り消せるのは、その人のその種類の最後の出来事だけ(間を抜くと、あとの出来事の前提が変わるため)。
# 登記の申請に入れた出来事は取り消せない。
class Person::ChangeCancellation < ApplicationRecord
  include EventRecord
  event_of :cancelled_at, entry: :cancel!

  belongs_to :change, polymorphic: true
  belongs_to :canceller, class_name: "User", optional: true
  validates :reason, presence: true

  def self.model_name_label = "住所・氏名の出来事の取消"

  def self.cancel!(change, by:, reason:, at: Time.current)
    reason = reason.to_s.strip
    raise ArgumentError, "取り消す理由を書いてください" if reason.empty?
    raise ArgumentError, "すでに取り消してあります" if change.cancelled?

    person = Person.find(change.person_id)
    latest = change.is_a?(Person::AddressChange) ? person.latest_address_change : person.latest_name_change
    raise ArgumentError, "取り消せるのは、いちばん新しい出来事だけです" unless latest == change

    registration = change.registration
    raise ArgumentError, "登記の申請に入れてあるので取り消せません" if registration&.registration_filing

    transaction do
      cancellation = create!(change:, canceller: by, reason:, cancelled_at: at)
      registration&.destroy!
      change.person.address_changes.reset
      change.person.name_changes.reset
      Audit.final!("#{person.name}の#{change.class.model_name_label}(#{change.date_label})を取り消した: #{reason}")
      cancellation
    end
  end
end
