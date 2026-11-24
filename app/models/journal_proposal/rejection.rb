# AI の提案の却下(イベント。日時は rejected_at)。仕訳は作らない。
class JournalProposal::Rejection < ApplicationRecord
  include EventRecord

  event_of :rejected_at, entry: :reject!

  belongs_to :journal_proposal
  belongs_to :rejecter, class_name: "User", optional: true

  # 却下する(作る入口)。処理済みの提案には何もしない。
  def self.reject!(proposal, by:, at: Time.current)
    return unless proposal.proposed?

    transaction do
      rejection = create!(journal_proposal: proposal, rejecter: by, rejected_at: at)
      proposal.voucher.advance_status!
      Audit.final!("AI の提案を却下した(証憑 ##{proposal.voucher_id})")
      rejection
    end
  end
end
