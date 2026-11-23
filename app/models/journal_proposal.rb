# AI が提案した仕訳。人が承認すると JournalEntry になる(承認なしに記帳しない)。
class JournalProposal < ApplicationRecord
  STATUSES = { "proposed" => "確認待ち", "approved" => "承認済み", "rejected" => "却下" }.freeze
  CONFIDENCES = { "high" => "高", "medium" => "中", "low" => "低" }.freeze

  belongs_to :voucher
  belongs_to :debit_account, class_name: "Account"
  belongs_to :credit_account, class_name: "Account"
  belongs_to :debit_department, class_name: "Department", optional: true
  belongs_to :credit_department, class_name: "Department", optional: true
  belongs_to :journal_entry, optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :entry_date, presence: true
  validates :amount, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES.keys }
  validates :confidence, inclusion: { in: CONFIDENCES.keys }

  def status_label = STATUSES[status]
  def confidence_label = CONFIDENCES[confidence]
  def proposed? = status == "proposed"

  # 承認して仕訳を作る。内容を直してから承認することもできる(attrs)。
  def approve!(user, attrs = {})
    transaction do
      assign_attributes(attrs)
      entry = JournalEntry.create!(
        entry_date: entry_date, amount: amount,
        debit_account: debit_account, debit_department: debit_department,
        credit_account: credit_account, credit_department: credit_department,
        summary: summary, sub_summary: sub_summary,
        memo: "証憑 ##{voucher_id} から AI が提案（#{ai_model}）",
        approved_by: user, approved_at: Time.current
      )
      update!(status: "approved", journal_entry: entry, reviewed_by: user, reviewed_at: Time.current)
      voucher.refresh_status!
      entry
    end
  end

  def reject!(user)
    update!(status: "rejected", reviewed_by: user, reviewed_at: Time.current)
    voucher.refresh_status!
  end
end
