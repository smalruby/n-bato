# AI の仕訳の提案(イベント。日時は proposed_at)。人が承認すると仕訳(JournalEntry)になる(承認なしに記帳しない)。
# 提案は書き換えない。人が直してから承認したときは、直した内容は承認でできた仕訳に入る(提案は AI が出したまま残る)。
# いまの状態は、詳細のイベント(承認・却下・取り下げ)の有無で決まる。docs/data-model.md
class JournalProposal < ApplicationRecord
  include EventRecord

  event_of :proposed_at, entry: :propose!

  STATUSES = {"proposed" => "確認待ち", "approved" => "承認済み", "rejected" => "却下", "withdrawn" => "取り下げ"}.freeze
  CONFIDENCES = {"high" => "高", "medium" => "中", "low" => "低"}.freeze
  ENTRY_FIELDS = %i[entry_date amount debit_account_id debit_department_id credit_account_id credit_department_id summary sub_summary].freeze

  belongs_to :voucher
  belongs_to :debit_account, class_name: "Account"
  belongs_to :credit_account, class_name: "Account"
  belongs_to :debit_department, class_name: "Department", optional: true
  belongs_to :credit_department, class_name: "Department", optional: true
  has_one :approval, class_name: "JournalProposal::Approval", dependent: nil
  has_one :rejection, class_name: "JournalProposal::Rejection", dependent: nil
  has_one :withdrawal, class_name: "JournalProposal::Withdrawal", dependent: nil
  has_one :journal_entry, through: :approval
  belongs_to :reproposed_from, class_name: "JournalProposal", optional: true

  validates :entry_date, presence: true
  validates :amount, numericality: {only_integer: true, greater_than: 0}
  validates :confidence, inclusion: {in: CONFIDENCES.keys}

  scope :approved, -> { where(id: Approval.select(:journal_proposal_id)) }
  scope :pending, lambda {
    where.not(id: Approval.select(:journal_proposal_id)).where.not(id: Rejection.select(:journal_proposal_id))
      .where.not(id: Withdrawal.select(:journal_proposal_id))
  }

  # 提案を作る(作る入口)。AI の答えから作る Bookkeeper::ProposalGenerator が使う。
  def self.propose!(voucher:, model:, at: Time.current, **attrs)
    create!(voucher:, ai_model: model, proposed_at: at, **attrs)
  end

  # 提案のし直し(作る入口の 1 つ)。承認でできた仕訳を取り消したとき、元の提案と同じ内容で確認待ちの提案を作る(AI は呼ばない)。docs/adr/0026
  def self.repropose!(original, at: Time.current)
    attrs = original.attributes.slice(*(ENTRY_FIELDS.map(&:to_s) + %w[rationale confidence])).symbolize_keys
    propose!(voucher: original.voucher, model: original.ai_model, at:, reproposed_from: original, **attrs)
  end

  def status
    if approval then "approved"
    elsif rejection then "rejected"
    elsif withdrawal then "withdrawn"
    else "proposed"
    end
  end

  def status_label = STATUSES[status]
  def confidence_label = CONFIDENCES[confidence]
  def proposed? = status == "proposed"
end
