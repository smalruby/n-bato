# 入会を認めなかった(イベント。日時は rejected_at)。理由は必ず書く(定款第7条第4項: 理由を付した書面で知らせる)。docs/adr/0030
class MemberApplication::Rejection < ApplicationRecord
  include EventRecord

  event_of :rejected_at, entry: :reject!

  belongs_to :member_application
  belongs_to :rejecter, class_name: "User", optional: true
  validates :reason, presence: true

  def self.reject!(application, reason:, by:, at: Time.current)
    reason = reason.to_s.strip
    raise ArgumentError, "認めない理由を書いてください" if reason.empty?
    raise ArgumentError, "届いた申込ではありません" unless application.received?

    transaction do
      rejection = create!(member_application: application, rejecter: by, reason:, rejected_at: at)
      application.update!(status: "rejected", reason:, decided_on: at.to_date)
      Audit.final!("#{application.name}さんの入会申込を認めないことにした")
      rejection
    end
  end
end
