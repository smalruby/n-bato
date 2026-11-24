# 仕訳の取消(イベントを作る)。docs/adr/0008・0026: コントローラーは確かめ・呼び出し・表示の準備だけ。
# 証憑の画面と仕訳の表の両方から呼ぶ。戻り先は back_to(voucher / sheet)で選ぶ。
class JournalEntries::CancellationsController < ApplicationController
  def create
    entry = JournalEntry.find(params[:journal_entry_id])
    JournalEntry::Cancellation.cancel!(entry, by: Current.user, reason: params[:reason])
    redirect_to back_path(entry), notice: notice_for(entry)
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to back_path(entry), alert: e.message
  end

  private

  def back_path(entry)
    voucher = entry.journal_proposal&.voucher
    (params[:back_to] == "voucher" && voucher) ? voucher_path(voucher) : journal_entries_path(year: entry.fiscal_year)
  end

  def notice_for(entry)
    base = "仕訳(伝票 #{entry.slip_number})を取り消しました"
    entry.journal_proposal ? "#{base}。同じ内容の提案を確認待ちでもう一度出しました。正しい科目を選んで承認してください" : base
  end
end
