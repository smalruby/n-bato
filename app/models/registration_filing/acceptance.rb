# 法務局が受け付けた(イベント。日付は accepted_on)。受付番号は「受付のお知らせ」で分かる。docs/adr/0031
class RegistrationFiling::Acceptance < ApplicationRecord
  include EventRecord
  event_of :accepted_on, entry: :accept!

  belongs_to :registration_filing
  belongs_to :recorded_by, class_name: "User", optional: true

  def self.model_name_label = "登記の申請の受付"

  def self.accept!(filing, accepted_on:, receipt_number: "", by: nil)
    raise ArgumentError, "まだ申請していません" unless filing.status == "submitted"

    transaction do
      event = create!(registration_filing: filing, accepted_on:, receipt_number: receipt_number.to_s.strip, recorded_by: by)
      filing.advance_status!
      Audit.final!("登記の申請が受け付けられた(#{accepted_on.strftime('%Y/%m/%d')}#{" 受付番号 #{event.receipt_number}" if event.receipt_number.present?})")
      event
    end
  end
end
