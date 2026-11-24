# AI の提案の取り下げ(イベント。日時は withdrawn_at)。AI に提案をやり直させたとき、確認待ちだった前の提案を取り下げる。
# これまでは前の提案を消していたが、提案は消さずに取り下げとして残す(docs/adr/0007)。
class JournalProposal::Withdrawal < ApplicationRecord
  include EventRecord

  event_of :withdrawn_at, entry: :withdraw!

  belongs_to :journal_proposal

  # 取り下げる(作る入口)。確認待ちの提案だけ。
  def self.withdraw!(proposal, at: Time.current)
    return unless proposal.proposed?

    create!(journal_proposal: proposal, withdrawn_at: at)
  end
end
