require "test_helper"

class VoucherFlowTest < ActionDispatch::IntegrationTest
  setup do
    import_sample
    sign_in
  end

  test "証憑を登録して、提案を直してから承認する" do
    post vouchers_path, params: { voucher: { kind: "receipt", issued_on: "2025-06-01", description: "ケーブルを買った",
                                             files: [ fixture_file_upload("receipt.png", "image/png") ] } }
    voucher = Voucher.last
    assert_redirected_to voucher_path(voucher)
    assert voucher.files.attached?

    proposal = voucher.journal_proposals.create!(
      entry_date: Date.new(2025, 6, 1), debit_account: Account.find_by!(code: 658), debit_department: Department.find_by!(code: 113),
      credit_account: Account.find_by!(code: 100), amount: 1980, summary: "消耗品を買った", rationale: "テスト", confidence: "high"
    )
    voucher.refresh_status!
    get voucher_path(voucher)
    assert_match "この内容で承認して記帳", response.body

    assert_difference -> { JournalEntry.count }, 1 do
      post approve_journal_proposal_path(proposal), params: { journal_proposal: { amount: 2080, sub_summary: "HDMI" } }
    end
    entry = JournalEntry.order(:id).last
    assert_equal 2080, entry.amount
    assert_equal "HDMI", entry.sub_summary
    assert_equal users(:one), entry.approved_by
    assert_equal "booked", voucher.reload.status

    assert_no_difference -> { JournalEntry.count } do
      post approve_journal_proposal_path(proposal)
    end
  end

  test "ファイルも説明も無い証憑は登録できない" do
    post vouchers_path, params: { voucher: { kind: "receipt", description: "" } }
    assert_response :unprocessable_entity
  end

  test "API キーが無いと AI の提案は使えない旨を表示する" do
    get vouchers_path
    assert_match "ANTHROPIC_API_KEY", response.body
  end
end
