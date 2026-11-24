# 申請を取り下げた(イベント。日付は withdrawn_on)。入れた登記の事由は、ほかの申請に入れ直せる。docs/adr/0031
class RegistrationFiling::Withdrawal < ApplicationRecord
  include EventRecord

  event_of :withdrawn_on, entry: :withdraw!

  belongs_to :registration_filing
  belongs_to :recorded_by, class_name: "User", optional: true
  validates :reason, presence: true

  def self.withdraw!(filing, withdrawn_on:, reason:, by: nil)
    reason = reason.to_s.strip
    raise ArgumentError, "取り下げる理由を書いてください" if reason.empty?
    raise ArgumentError, "もう終わった申請です" if filing.finished?

    transaction do
      event = create!(registration_filing: filing, withdrawn_on:, reason:, recorded_by: by)
      filing.advance_status!
      Audit.final!("登記の申請を取り下げた(#{withdrawn_on.strftime("%Y/%m/%d")}): #{reason}")
      event
    end
  end
end
