require "test_helper"

# 証憑(長いイベント)の画面と、提案の承認・却下(イベントを作る create)。docs/adr/0008
class VoucherEventsFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    import_sample
    sign_in
    @voucher = Voucher.create!(kind: "receipt", issued_on: Date.new(2025, 6, 1), description: "ケーブル")
  end

  def propose
    JournalProposal.propose!(voucher: @voucher, model: "test", entry_date: Date.new(2025, 6, 1), amount: 1980,
                             debit_account: Account.find_by!(code: 658), credit_account: Account.find_by!(code: 100),
                             summary: "消耗品を買った", rationale: "テスト", confidence: "high").tap { @voucher.advance_status! }
  end

  test "却下は create で作り、承認でできない内容ならエラーを出す" do
    p = propose
    post journal_proposal_approval_path(p), params: { journal_proposal: { entry_date: "" } }
    assert_redirected_to voucher_path(@voucher)
    assert_match "日付", flash[:alert].to_s + JournalEntry.human_attribute_name(:entry_date)
    assert p.reload.proposed?

    post journal_proposal_rejection_path(p)
    assert_redirected_to voucher_path(@voucher)
    assert_equal "rejected", p.reload.status
    get voucher_path(@voucher)
    assert_response :success
  end

  test "証憑を直す・新しく作る画面" do
    get new_voucher_path
    assert_response :success
    get edit_voucher_path(@voucher)
    assert_response :success
    patch voucher_path(@voucher), params: { voucher: { description: "ケーブル 2 本" } }
    assert_redirected_to voucher_path(@voucher)
    assert_equal "ケーブル 2 本", @voucher.reload.description
    patch voucher_path(@voucher), params: { voucher: { kind: "nope" } }
    assert_response :unprocessable_entity
  end

  test "AI に頼む・記帳しない" do
    assert_enqueued_with(job: ProposeJournalEntriesJob) { post propose_voucher_path(@voucher) }
    assert_equal "proposing", @voucher.reload.status
    post reject_voucher_path(@voucher)
    assert_equal "rejected", @voucher.reload.status
  end

  test "提案のある証憑は消せない。提案の無い証憑は消せる" do
    propose
    assert_no_difference -> { Voucher.count } do
      delete voucher_path(@voucher)
    end
    assert_match "削除できません", flash[:alert]
    other = Voucher.create!(kind: "memo", description: "メモ")
    assert_difference -> { Voucher.count }, -1 do
      delete voucher_path(other)
    end
  end
end
