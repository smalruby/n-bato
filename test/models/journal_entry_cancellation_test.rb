require "test_helper"

# 記帳した仕訳の取消(docs/adr/0026)
class JournalEntryCancellationTest < ActiveSupport::TestCase
  setup do
    Kaikeiou::SiwakeImporter.new(file_fixture("siwake_sample.txt").binread, filename: "s.txt").import
    @user = users(:one)
    @voucher = Voucher.create!(kind: "bank", issued_on: Date.new(2025, 6, 1), description: "通帳")
    @proposal = JournalProposal.propose!(voucher: @voucher, model: "test", entry_date: Date.new(2025, 6, 1), amount: 20,
      debit_account: Account.find_by!(code: 106), credit_account: Account.find_by!(code: 550),
      summary: "預金利息を受け取る", sub_summary: "", rationale: "テスト", confidence: "high")
    @voucher.advance_status!
    Audit.operation(user: @user, scope: "vouchers") do
      @entry = JournalProposal::Approval.approve!(@proposal, by: @user, entry: {debit_account_id: Account.find_by!(code: 658).id}).journal_entry
    end
  end

  def cancel(entry = @entry, reason: "選び間違い")
    Audit.operation(user: @user, scope: "journal_entries") { JournalEntry::Cancellation.cancel!(entry, by: @user, reason:) }
  end

  test "取り消すと帳簿から外れ、同じ内容の提案が確認待ちでもう一度でき、証憑は確認待ちに戻る" do
    assert_equal "booked", @voucher.reload.status
    assert_not @entry.editable?, "承認でできた仕訳は表で直さない"

    cancel
    assert @entry.reload.cancelled?
    assert_not @entry.cancellable?
    assert_not_includes JournalEntry.active, @entry
    assert_includes JournalEntry.cancelled, @entry
    assert_equal "proposed", @voucher.reload.status
    again = @voucher.journal_proposals.pending.sole
    assert_equal @proposal, again.reproposed_from
    assert_equal [106, 550, 20], [again.debit_account.code, again.credit_account.code, again.amount], "人が直す前の、元の提案の内容"
    assert_equal "approved", @proposal.reload.status

    assert_empty ModelVerification.mismatches
    assert_equal "final", AuditOperation.order(:id).last.kind
  end

  test "理由が空なら取り消さない。2 回は取り消さない。会計王から取り込んだ仕訳は取り消さない" do
    assert_raises(ArgumentError) { cancel(reason: " ") }
    assert_not @entry.reload.cancelled?
    cancel
    assert_raises(ArgumentError) { cancel }
    imported = JournalEntry.where.not(siwake_import_id: nil).first
    assert_raises(ArgumentError) { cancel(imported) }
  end

  test "取り消した仕訳は会計王への書き出しと残高に数えない" do
    year = @entry.fiscal_year
    rows = -> { JournalEntry.active.in_fiscal_year(year).count }
    n = rows.call
    cancel
    assert_equal n - 1, rows.call
    assert_not_includes Ledger::Book.new.instance_variable_get(:@entries), @entry
  end

  test "締めた年度の仕訳を取り消すと、締めた年度を直したことが残る" do
    period = FiscalPeriod.for(@entry.fiscal_year)
    period.update_columns(closed_on: Date.current)
    cancel(reason: "締めた年度の誤り")
    assert @entry.reload.cancelled?
    assert_equal "締めた年度の誤り", AuditOperation.order(:id).last.reason
  end
end
