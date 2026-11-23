require "test_helper"

# 仕訳の取消の画面(デザインシステム「仕訳の取消」、docs/adr/0026)
class JournalEntryCancellationFlowTest < ActionDispatch::IntegrationTest
  setup do
    import_sample
    sign_in
    @voucher = Voucher.create!(kind: "bank", issued_on: Date.new(2025, 6, 1), description: "通帳")
    p = JournalProposal.propose!(voucher: @voucher, model: "test", entry_date: Date.new(2025, 6, 1), amount: 20,
                                 debit_account: Account.find_by!(code: 106), credit_account: Account.find_by!(code: 550),
                                 summary: "預金利息を受け取る", rationale: "テスト", confidence: "high")
    @voucher.advance_status!
    post journal_proposal_approval_path(p), params: { journal_proposal: { debit_account_id: Account.find_by!(code: 658).id } }
    @entry = p.reload.journal_entry
  end

  test "証憑の画面から取り消すと、確認待ちの提案がもう一度出て、取り消した仕訳に札と理由が付く" do
    get voucher_path(@voucher)
    assert_select "form[action='#{journal_entry_cancellation_path(@entry)}'] input[name=reason][required]"

    post journal_entry_cancellation_path(@entry), params: { reason: "", back_to: "voucher" }
    assert_redirected_to voucher_path(@voucher)
    assert_match "理由", flash[:alert]
    assert_not @entry.reload.cancelled?

    post journal_entry_cancellation_path(@entry), params: { reason: "選び間違い", back_to: "voucher" }
    assert_redirected_to voucher_path(@voucher)
    assert_match "確認待ちでもう一度", flash[:notice]
    follow_redirect!
    assert_select ".nb-cancelled-tag", "取消"
    assert_match "選び間違い", response.body
    assert_select "input[type=submit][value='この内容で承認して記帳']", 1
  end

  test "仕訳の表: 承認でできた仕訳は直せず「取り消す」を出す。取り消した仕訳はふだん出さず、絞り込みで取消線つきで出す" do
    year = @entry.fiscal_year
    get journal_entries_path(year:)
    assert_select "##{ActionView::RecordIdentifier.dom_id(@entry)} form[action='#{journal_entry_cancellation_path(@entry)}']"
    assert_select "##{ActionView::RecordIdentifier.dom_id(@entry)} input[name='journal_entry[amount]']", 0

    post journal_entry_cancellation_path(@entry), params: { reason: "表から取り消す", back_to: "sheet" }
    assert_redirected_to journal_entries_path(year:)
    get journal_entries_path(year:)
    assert_select "##{ActionView::RecordIdentifier.dom_id(@entry)}", 0

    get journal_entries_path(year:, cancelled: "1")
    assert_select "tr.is-cancelled##{ActionView::RecordIdentifier.dom_id(@entry)} .nb-cancelled-tag", "取消"
    assert_select "tr.is-cancelled td.nb-struck", minimum: 1
    assert_match "表から取り消す", response.body
    get journal_entries_path(year:, cancelled: "0")
    assert_select "##{ActionView::RecordIdentifier.dom_id(@entry)}", 0
  end

  test "承認でできた仕訳は表で書き換えも削除もしない" do
    patch journal_entry_path(@entry, format: :json), params: { journal_entry: { amount: 999 } }
    assert_response :forbidden
    delete journal_entry_path(@entry)
    assert JournalEntry.exists?(@entry.id)
  end
end
