require "test_helper"

# AI の提案のイベント(承認・却下・取り下げ)と、証憑のいまの状態(docs/adr/0002・0005・0007)。
class JournalProposalEventsTest < ActiveSupport::TestCase
  setup do
    Kaikeiou::SiwakeImporter.new(file_fixture("siwake_sample.txt").binread, filename: "s.txt").import
    @user = users(:one)
    @voucher = Voucher.create!(kind: "receipt", description: "ケーブル", issued_on: Date.new(2025, 6, 1))
  end

  def propose(amount: 1980)
    JournalProposal.propose!(voucher: @voucher, model: "test", entry_date: Date.new(2025, 6, 1), amount:,
                             debit_account: Account.find_by!(code: 658), debit_department: Department.find_by!(code: 113),
                             credit_account: Account.find_by!(code: 100), summary: "消耗品を買った", rationale: "テスト", confidence: "high")
  end

  test "提案は日時 1 つで作り、確認待ち" do
    p = propose
    assert p.proposed_at
    assert_equal "proposed", p.status
    assert_equal "確認待ち", p.status_label
    assert_equal "高", p.confidence_label
    @voucher.advance_status!
    assert_equal "proposed", @voucher.status
    assert_equal [ p ], @voucher.open_proposals.to_a
  end

  test "承認すると仕訳を作り、直した内容は仕訳に入り、提案はそのまま" do
    p = propose
    approval = Audit.operation(user: @user, scope: "vouchers") do
      JournalProposal::Approval.approve!(p, by: @user, entry: { amount: 2080, sub_summary: "HDMI", debit_department_id: "" })
    end
    entry = approval.journal_entry
    assert_equal 2080, entry.amount
    assert_nil entry.debit_department, "空にした部門は空になる"
    assert_equal 1980, p.reload.amount
    assert_equal "approved", p.status
    assert_equal entry, p.journal_entry
    assert_equal @user, approval.approver
    assert_equal approval.approved_at, approval.occurred_at
    assert_equal "booked", @voucher.reload.status
    assert_equal "final", AuditOperation.order(:id).last.kind
    assert_raises(ArgumentError) { JournalProposal::Approval.approve!(p, by: @user) }
    assert_not entry.destroy, "承認でできた仕訳は消さない"
  end

  test "却下は仕訳を作らず、処理済みには何もしない" do
    p = propose
    assert_no_difference -> { JournalEntry.count } do
      JournalProposal::Rejection.reject!(p, by: @user)
    end
    assert_equal "rejected", p.reload.status
    assert_equal "pending", @voucher.reload.status
    assert_nil JournalProposal::Rejection.reject!(p, by: @user)
    assert_nil JournalProposal::Withdrawal.withdraw!(p)
  end

  test "取り下げた提案は確認待ちから外れる。提案のある証憑は消せない" do
    p = propose
    JournalProposal::Withdrawal.withdraw!(p)
    assert_equal "withdrawn", p.reload.status
    assert_empty JournalProposal.pending
    assert_not @voucher.destroy
  end

  test "手で決める状態(作業中・エラー・記帳しない)は、イベントから決めずにそのまま" do
    @voucher.update!(status: "rejected")
    propose
    assert_equal "rejected", @voucher.derived_status
  end

  test "model:verify: いまの状態がイベントと食い違うと知らせる" do
    propose
    @voucher.advance_status!
    assert_empty ModelVerification.mismatches
    @voucher.update_column(:status, "booked")
    assert_equal 1, ModelVerification.mismatches.size
  end
end
