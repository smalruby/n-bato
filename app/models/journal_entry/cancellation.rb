# 記帳した仕訳の取消(イベント。日時は cancelled_at)。docs/adr/0026
# 取り消した仕訳は消さず、帳簿・計算書類・残高・会計王への書き出しから外す(JournalEntry.active)。
# 証憑から記帳した仕訳なら、元の提案と同じ内容の提案を確認待ちでもう一度作る(AI は呼ばない)。元に戻せない操作。
class JournalEntry::Cancellation < ApplicationRecord
  include EventRecord
  event_of :cancelled_at, entry: :cancel!

  belongs_to :journal_entry
  belongs_to :canceller, class_name: "User", optional: true

  validates :reason, presence: true

  # 取り消す(作る入口)。理由は必ず書く。会計王から取り込んだ仕訳と、取り消し済みの仕訳は取り消せない。
  def self.cancel!(entry, by:, reason:, at: Time.current)
    reason = reason.to_s.strip
    raise ArgumentError, "取り消す理由を書いてください" if reason.empty?
    raise ArgumentError, "この仕訳はすでに取り消してあります" if entry.cancelled?
    raise ArgumentError, "会計王から取り込んだ仕訳は、会計王で直して取り込み直してください" if entry.imported?

    transaction do
      if FiscalPeriod.for(entry.fiscal_year)&.closed?
        Audit.reason!(reason)
        FiscalPeriod.changed_after_close!(entry.fiscal_year)
      end
      cancellation = create!(journal_entry: entry, canceller: by, reason:, cancelled_at: at)
      if (proposal = entry.journal_proposal)
        JournalProposal.repropose!(proposal, at:)
        proposal.voucher.advance_status!
      end
      Audit.final!("仕訳を取り消した(伝票 #{entry.slip_number}・#{entry.entry_date.strftime('%Y/%m/%d')}・#{entry.amount.to_fs(:delimited)}円): #{reason}")
      cancellation
    end
  end
end
