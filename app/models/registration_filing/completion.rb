# 登記が完了した(イベント。日付は completed_on)。docs/adr/0031
# 入れた登記の事由を「登記した」にし、登記の完了を待っているやること(resume_rule = registration_completed)を作業中に戻す。
class RegistrationFiling::Completion < ApplicationRecord
  include EventRecord

  event_of :completed_on, entry: :complete!

  belongs_to :registration_filing
  belongs_to :recorded_by, class_name: "User", optional: true

  def self.complete!(filing, completed_on:, by: nil)
    raise ArgumentError, "申請していないか、もう終わった申請です" unless %w[submitted accepted correcting].include?(filing.status)

    transaction do
      event = create!(registration_filing: filing, completed_on:, recorded_by: by)
      filing.registrations.each { it.update!(registered_on: completed_on) }
      filing.advance_status!
      resumed = Todo.resume!("registration_completed", note: "登記が完了した(#{completed_on.strftime("%Y/%m/%d")})")
      Audit.final!("登記が完了した(#{completed_on.strftime("%Y/%m/%d")})#{"。待っていたやること #{resumed.size} 件を作業中にした" if resumed.any?}")
      event
    end
  end
end
