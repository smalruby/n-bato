require "test_helper"

class SheetAndProcedureTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    @cash = Account.create!(fiscal_year: 2024, code: 100, name: "現      金")
    @supplies = Account.create!(fiscal_year: 2024, code: 658, name: "消耗品費(事業)")
    @entry = JournalEntry.create!(entry_date: Date.new(2024, 5, 1), debit_account: @supplies, credit_account: @cash, amount: 1000, summary: "文具")
    FiscalPeriod.ensure!
  end

  test "今日が年度の外なら、新しい行の日付はその年度のいちばん後の仕訳の日付で始まる" do
    get journal_entries_path(year: 2024)
    assert_select "tr.is-new input[name='journal_entry[entry_date]'][value='2024-05-01']"
  end

  test "科目の候補は最初は使ったものだけ。すべては別に取りに行く" do
    unused = Account.create!(fiscal_year: 2024, code: 700, name: "給料手当")
    get journal_entries_path(year: 2024)
    script = css_select("#picker-accounts").first
    used = JSON.parse(script.text).map { it["code"] }
    assert_equal %w[100 658], used.sort
    assert_equal "3", script["data-total"]

    get picker_path("accounts")
    assert_includes response.parsed_body["items"].map { it["code"] }, unused.code.to_s
  end

  test "仕訳のシートでセルを直すとすぐ保存し、元に戻せる" do
    get journal_entries_path(year: 2024)
    assert_response :success
    assert_select "input[name='journal_entry[amount]'][value='1000']"
    assert_select "button", text: /元に戻す/

    patch journal_entry_path(@entry, format: :json), params: { journal_entry: { amount: "1,280" }, undo_scope: "journal_entries" }
    assert_response :success
    body = response.parsed_body
    assert body["ok"]
    assert_equal 1, body["undo"]
    assert_equal 1280, @entry.reload.amount

    post undo_path(format: :json), params: { scope: "journal_entries" }, as: :json
    assert response.parsed_body["ok"]
    assert_equal 1000, @entry.reload.amount

    get history_path(scope: "journal_entries")
    assert_match "元に戻した", response.body
  end

  test "上部バーに操作する年度を出し、他の年度に切り替えられる" do
    get journal_entries_path(year: 2024)
    assert_select ".nb-bar .nb-year-chip", text: /2024年度/
    assert_select ".nb-year-menu a[href='#{year_switch_path(FiscalYear.current.year)}']"
    assert_select "body[data-year-hue='#{FiscalPeriod.hue(2024)}']"

    get year_switch_path(FiscalYear.current.year), headers: { "Referer" => "http://www.example.com/journal_entries?year=2024" }
    assert_redirected_to "/journal_entries"
    follow_redirect!
    assert_select ".nb-bar .nb-year-chip", text: /#{FiscalYear.current.year}年度/
    assert_select "p", text: /この年度の仕訳はありません。/
    assert_select "tr.is-new"
  end

  test "年度の外の日付は保存せずに知らせ、移すと選んだら移す" do
    patch journal_entry_path(@entry, format: :json), params: { journal_entry: { entry_date: "2025-04-01" }, sheet_year: 2024, undo_scope: "journal_entries" }
    assert_response :conflict
    assert_equal "outside_year", response.parsed_body["code"]
    assert_equal 2024, @entry.reload.fiscal_year

    patch journal_entry_path(@entry, format: :json), params: { journal_entry: { entry_date: "2025-04-01" }, sheet_year: 2024, move: "1", undo_scope: "journal_entries" }
    body = response.parsed_body
    assert body["ok"]
    assert_equal journal_entries_path(year: 2025), body["location"]
    assert_equal 2025, @entry.reload.fiscal_year
  end

  test "締めた年度の仕訳は、理由を書かないと直せず、理由は変更の記録に残る" do
    FiscalPeriod.for(2024).update!(closed_on: Date.current)
    patch journal_entry_path(@entry, format: :json), params: { journal_entry: { amount: "1,500" }, sheet_year: 2024, undo_scope: "journal_entries" }
    assert_response :conflict
    assert_equal "reason_required", response.parsed_body["code"]
    assert_equal 1000, @entry.reload.amount

    patch journal_entry_path(@entry, format: :json), params: { journal_entry: { amount: "1,500" }, sheet_year: 2024, reason: "領収書の読み違い", undo_scope: "journal_entries" }
    assert response.parsed_body["ok"]
    assert_equal 1500, @entry.reload.amount
    op = AuditOperation.where(scope: "journal_entries").order(:id).last
    assert_equal "領収書の読み違い", op.reason
    assert_match "締めた年度", op.label
  end

  test "前の年度を締める前の年度は仮と出し、会計王へは書き出させない" do
    get journal_entries_path(year: 2025)
    assert_select ".nb-year-band", text: /2024年度\(令和6年度\)をまだ締めていません/
    assert_select "button[disabled]", text: "新規分を SIWAKE で書き出す"
  end

  test "表のいちばん下の行から仕訳を足すと、行の ID と年度の表の場所を返す" do
    post journal_entries_path(format: :json), params: { undo_scope: "journal_entries", sheet_year: 2025, journal_entry: {
      entry_date: "2025-05-01", debit_account_id: @supplies.id, credit_account_id: @cash.id, amount: "2,000", summary: "紙" } }
    body = response.parsed_body
    assert body["ok"]
    entry = JournalEntry.order(:id).last
    assert_equal "journal_entry_#{entry.id}", body["record"]
    assert_equal journal_entries_path(year: 2025), body["location"]
    assert_equal 1, body["undo"]
    assert_equal "追加した仕訳", body.dig("undo_peek", "item")
  end

  test "元に戻すボタンに戻る項目を出し、戻したら記録のある年度の表を返す" do
    patch journal_entry_path(@entry, format: :json), params: { journal_entry: { amount: "1,280" }, undo_scope: "journal_entries" }
    body = response.parsed_body
    assert_equal "金額", body.dig("undo_peek", "item")
    assert_equal "金額 1,280 → 1,000", body.dig("undo_peek", "detail")

    get journal_entries_path(year: 2024)
    assert_select "button[data-undo-target=undoButton] [data-undo-target=undoItem]", text: ": 金額"

    post undo_path(format: :json), params: { scope: "journal_entries" }, as: :json
    body = response.parsed_body
    assert_equal journal_entries_path(year: 2024), body["location"]
    assert_equal({ "record" => "journal_entry_#{@entry.id}", "field" => "amount" }, body["highlight"])
  end

  test "科目で絞り込むと、件数と科目の残高を出し、画面を離れても保つ" do
    other = Account.create!(fiscal_year: 2024, code: 101, name: "普通預金")
    JournalEntry.create!(entry_date: Date.new(2024, 6, 1), debit_account: other, credit_account: @cash, amount: 500, summary: "預け入れ")
    get journal_entries_path(year: 2024, account_id: other.id)
    assert_select "tbody tr[id^=journal_entry_]", 1
    assert_select ".nb-tag", text: /絞り込み中: 普通預金/
    assert_select "[data-stat=balance]", text: /普通預金の残高/
    get journal_entries_path(year: 2024)
    assert_select "tbody tr[id^=journal_entry_]", 1
    get journal_entries_path(year: 2024, clear: 1)
    assert_select "tbody tr[id^=journal_entry_]", 2
  end

  test "会計王から取り込んだ行には、直せない理由を持たせる" do
    import_sample
    imported = JournalEntry.where.not(siwake_import_id: nil).first
    get journal_entries_path(year: imported.fiscal_year)
    assert_select "tr[data-readonly-reason*='会計王で直して']"
  end

  test "保存できないときは理由を返す" do
    patch journal_entry_path(@entry, format: :json), params: { journal_entry: { entry_date: "" } }
    assert_response :unprocessable_entity
    assert_match "保存できませんでした", response.parsed_body["message"]
  end

  test "会計王から取り込んだ仕訳は変えられない" do
    import_sample
    imported = JournalEntry.where.not(siwake_import_id: nil).first
    patch journal_entry_path(imported, format: :json), params: { journal_entry: { summary: "x" } }
    assert_response :forbidden
  end

  test "手続きを始め、確かめたことをチェックし、手順を済みにする" do
    AnnualReport.draft_for(2025).save!
    post procedures_path, params: { kind: "annual_report", period: 2025 }
    run = ProcedureRun.last
    follow_redirect!
    assert_response :success
    assert_match "決算を締める", response.body
    assert_match %r{定款 <a[^>]*data-turbo-frame="article_ref"[^>]*>第49条</a>}, response.body

    patch procedure_step_path(run, "close_books", format: :json), params: { checks: { "通帳を記帳した" => "1" }, undo_scope: "procedure:#{run.id}" }
    assert response.parsed_body["ok"], response.body
    assert_equal "current", run.reload.step("close_books").status

    post complete_procedure_step_path(run, "close_books")
    assert_equal "done", run.reload.step("close_books").status

    post undo_path, params: { scope: "procedure:#{run.id}" }
    assert_equal "current", run.reload.step("close_books").status, "済みにしたのを元に戻せる"
  end

  test "提出は元に戻せず、事業報告の提出日も入る" do
    report = AnnualReport.draft_for(2025)
    report.save!
    run = ProcedureRun.create!(kind: "annual_report", period: 2025)
    post complete_procedure_step_path(run, "submit")
    assert_equal Date.current, report.reload.submitted_on
    assert_equal "final", AuditOperation.last.kind
    post reopen_procedure_step_path(run, "submit")
    assert_equal Date.current, report.reload.submitted_on
  end

  test "返事がそろうまで済みにできない" do
    run = ProcedureRun.create!(kind: "annual_report", period: 2025)
    post complete_procedure_step_path(run, "audit")
    assert_equal "todo", run.reload.step("audit").status
  end
end
