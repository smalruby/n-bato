# AI の提案の承認(イベント。日時は approved_at)。承認すると仕訳(JournalEntry)を 1 件作り、証憑のいまの状態を進める。
# 元に戻せない操作(記帳)。訂正は、仕訳を取り消す仕訳と正しい仕訳で行う(docs/adr/0007)。
class JournalProposal::Approval < ApplicationRecord
  include EventRecord
  event_of :approved_at, entry: :approve!

  belongs_to :journal_proposal
  belongs_to :approver, class_name: "User", optional: true
  belongs_to :journal_entry

  # 承認する(作る入口)。entry は人が画面で直した仕訳の内容(省くと提案のまま)。
  def self.approve!(proposal, by:, entry: {}, at: Time.current)
    raise ArgumentError, "この提案はすでに処理済みです" unless proposal.proposed?

    transaction do
      fields = JournalProposal::ENTRY_FIELDS.map(&:to_s)
      # 画面から来た値で上書きする。空の選択(部門なし)は nil に、空の文字(補助摘要など)は空の文字のまま(NOT NULL の列があるため)
      given = entry.to_h.stringify_keys.slice(*fields).to_h { |k, v| [ k, k.end_with?("_id") ? v.presence : v.to_s ] }
      attrs = proposal.attributes.slice(*fields).merge(given)
      attrs["sub_summary"] = attrs["sub_summary"].to_s
      journal_entry = JournalEntry.create!(
        **attrs.symbolize_keys,
        memo: "証憑 ##{proposal.voucher_id} から AI が提案（#{proposal.ai_model}）",
        approved_by: by, approved_at: at
      )
      approval = create!(journal_proposal: proposal, approver: by, journal_entry:, approved_at: at)
      proposal.voucher.advance_status!
      Audit.final!("仕訳を承認して記帳した(証憑 ##{proposal.voucher_id})")
      approval
    end
  end
end
