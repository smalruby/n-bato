require "test_helper"

class AccountingFlowTest < ActionDispatch::IntegrationTest
  test "ログインしていないとログイン画面へ" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "SIWAKE ファイルをアップロードして取り込む" do
    sign_in
    file = fixture_file_upload("siwake_sample.txt", "text/plain")
    assert_difference -> { JournalEntry.count }, 6 do
      post siwake_imports_path, params: {files: [file]}
    end
    follow_redirect!
    assert_match "6 件を取り込みました", response.body
  end

  test "形式の違うファイルはエラーを表示する" do
    sign_in
    file = Rack::Test::UploadedFile.new(StringIO.new("a,b\r\n"), "text/plain", original_filename: "bad.txt")
    post siwake_imports_path, params: {files: [file]}
    follow_redirect!
    assert_match "読み込めません", response.body
  end

  test "年度と計算書類を表示する" do
    import_sample
    ensure_organization
    sign_in
    get root_path
    assert_response :success
    get fiscal_year_path(2024)
    assert_response :success
    Ledger::Report::KINDS.each_key do |kind|
      get fiscal_year_statement_path(2024, kind)
      assert_response :success
    end
    get fiscal_year_statement_path(2024, "activity")
    assert_match "経常収益計", response.body
    assert_match "7,003", response.body
  end

  test "仕訳を手で入力し、新規分だけ SIWAKE で書き出す" do
    import_sample
    sign_in
    cash = Account.find_by!(code: 100)
    supplies = Account.find_by!(code: 658)
    dept = Department.find_by!(code: 113)
    post journal_entries_path, params: {journal_entry: {
      entry_date: "2024-12-01", amount: "1,500", debit_account_id: supplies.id, debit_department_id: dept.id,
      credit_account_id: cash.id, summary: "消耗品を買った", sub_summary: "USB ケーブル"
    }}
    entry = JournalEntry.order(:id).last
    assert_equal 1500, entry.debit_amount
    assert_equal 1500, entry.credit_amount
    assert_equal 7, entry.slip_number
    assert entry.editable?

    get fiscal_year_siwake_export_path(2024, only: "new")
    file = Kaikeiou::SiwakeFile.parse(response.body)
    assert_equal 1, file.rows.size
    assert_equal "USB ケーブル", file.rows.first.sub_summary
    assert_equal Date.new(2024, 12, 1), file.rows.first.entry_date
  end

  test "会計王から取り込んだ仕訳は変更できない" do
    import_sample
    sign_in
    entry = JournalEntry.first
    get edit_journal_entry_path(entry)
    assert_redirected_to journal_entry_path(entry)
    assert_no_difference -> { JournalEntry.count } do
      delete journal_entry_path(entry)
    end
  end

  test "取り込みの取り消し" do
    si = import_sample.siwake_import
    sign_in
    assert_difference -> { JournalEntry.count }, -6 do
      delete siwake_import_path(si)
    end
  end

  test "PDF を出力する" do
    import_sample
    sign_in
    get fiscal_year_statement_path(2024, "balance_sheet", format: :pdf)
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert response.body.start_with?("%PDF")
    assert_match "貸借対照表", PdfRenderer::Fake.last_html # 印刷用の HTML を PDF にした
  end

  test "総勘定元帳と残高照合" do
    import_sample
    sign_in
    get fiscal_year_ledgers_path(2024)
    assert_response :success
    assert_match "消耗品費(事業)", response.body
    get fiscal_year_ledger_path(2024, 106)
    assert_response :success
    post balance_checks_path, params: {balance_check: {account_id: Account.find_by!(code: 106).id, checked_on: "2025-03-31", actual_amount: 3003}}
    follow_redirect!
    assert_match "帳簿と一致しました", response.body
    assert_pdf fiscal_year_ledgers_path(2024, format: :pdf)
  end
end
