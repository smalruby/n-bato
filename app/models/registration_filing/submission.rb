# 登記を申請した(イベント。日付は submitted_on)。申請番号は「到達のお知らせ」で分かる。docs/adr/0031
class RegistrationFiling::Submission < ApplicationRecord
  include EventRecord

  event_of :submitted_on, entry: :submit!

  belongs_to :registration_filing
  belongs_to :recorded_by, class_name: "User", optional: true

  def self.submit!(filing, submitted_on:, application_number: "", by: nil)
    raise ArgumentError, "書類を作っている申請ではありません" unless filing.drafting?
    raise ArgumentError, "登記することが入っていません" if filing.registrations.empty?

    transaction do
      event = create!(registration_filing: filing, submitted_on:, application_number: application_number.to_s.strip, recorded_by: by)
      filing.advance_status!
      Audit.final!("登記を申請した(#{submitted_on.strftime("%Y/%m/%d")}#{" 申請番号 #{event.application_number}" if event.application_number.present?})")
      event
    end
  end
end
