# 法務局から補正を求められた(イベント。日付は noticed_on)。何度でも起こりうる。docs/adr/0031
class RegistrationFiling::Correction < ApplicationRecord
  include EventRecord

  event_of :noticed_on, entry: :record!

  belongs_to :registration_filing
  belongs_to :recorded_by, class_name: "User", optional: true
  validates :note, presence: true

  def self.model_name_label = "登記の申請の補正"

  def self.record!(filing, noticed_on:, note:, by: nil)
    note = note.to_s.strip
    raise ArgumentError, "求められたことを書いてください" if note.empty?
    raise ArgumentError, "申請していないか、もう終わった申請です" unless %w[submitted accepted correcting].include?(filing.status)

    transaction do
      event = create!(registration_filing: filing, noticed_on:, note:, recorded_by: by)
      filing.advance_status!
      Audit.final!("登記の申請で補正を求められた(#{noticed_on.strftime("%Y/%m/%d")}): #{note}")
      event
    end
  end
end
