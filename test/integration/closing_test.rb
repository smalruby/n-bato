require "test_helper"

# 年度を締める・締めを解く・次の年度を始める・再提出(デザインシステム「年度」)
class ClosingTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    [2024, 2025].each do |y|
      Account.create!(fiscal_year: y, code: 100, name: "現金")
      Account.create!(fiscal_year: y, code: 510, name: "受取寄付金")
    end
    FiscalPeriod.ensure!
    FiscalPeriod.where(year: ...2024).update_all(closed_on: Date.current)
    JournalEntry.create!(entry_date: Date.new(2024, 6, 1), debit_account: Account.for_year(2024, 100), credit_account: Account.for_year(2024, 510), amount: 3000)
    @report = AnnualReport.draft_for(2024).tap(&:save!)
    post procedures_path, params: {kind: "annual_report", period: 2024}
    @run = ProcedureRun.find_by!(kind: "annual_report", period: 2024)
  end

  test "提出を記録するまでは締められず、締めると次の年度の期首の残高ができる" do
    get procedure_path(@run, step: "close_year")
    assert_select ".nb-disabled-action button[aria-disabled=true]", text: "この年度を締める"
    assert_select ".nb-tip", text: /まだ締められません.*提出した日がまだ記録されていません/

    AnnualReport::Milestone.record!(@report, "submitted", on: Date.new(2026, 11, 24))
    post procedure_step_status_changes_path(@run, "close_year"), params: {status: "done", completed_on: "2026-11-25"}
    assert FiscalPeriod.for(2024).reload.closed?
    assert_equal 3000, OpeningBalance.find_by!(fiscal_year: 2025, account: Account.for_year(2025, 100)).amount
    assert_not FiscalPeriod.for(2025).provisional?
  end

  test "締めた年度を直したら、再提出の手順が出る" do
    AnnualReport::Milestone.record!(@report, "submitted", on: Date.new(2026, 11, 24))
    FiscalPeriod.for(2024).close!
    assert_equal "skipped", @run.step("resubmit").status

    entry = JournalEntry.first
    patch journal_entry_path(entry, format: :json), params: {journal_entry: {amount: "3,500"}, sheet_year: 2024, reason: "金額の誤り", undo_scope: "journal_entries"}
    assert response.parsed_body["ok"]
    assert @report.reload.resubmit_needed_on
    assert_not_equal "skipped", ProcedureRun.find(@run.id).step("resubmit").status
  end

  test "締めを解くには理由が要り、新しい年度が締めてあると解けない" do
    FiscalPeriod.for(2024).close!
    post reopen_fiscal_period_path(2024), params: {reason: ""}
    assert FiscalPeriod.for(2024).reload.closed?
    post reopen_fiscal_period_path(2024), params: {reason: "監査で誤りが見つかった"}
    assert_not FiscalPeriod.for(2024).reload.closed?
  end

  test "次の年度を始めると、前の年度の科目・会員の記録を写す" do
    Current.working_year = 2025
    person = Person.create!(name: "会員A", address: "テスト市")
    Current.working_year = nil
    last = FiscalPeriod.maximum(:year)
    post start_next_fiscal_periods_path
    assert FiscalPeriod.for(last + 1)
    assert Account.for_year(last + 1, 100)
    assert_equal "テスト市", person.reload.record_for(last + 1)&.address if person.record_for(last)
  end

  test "変更の記録は年度ごとに並び、締めたあとの変更だけに絞れ、理由も出る" do
    FiscalPeriod.for(2024).close!(on: Date.current - 1)
    entry = JournalEntry.first
    patch journal_entry_path(entry, format: :json), params: {journal_entry: {amount: "3,500"}, sheet_year: 2024, reason: "金額の誤り", undo_scope: "journal_entries"}
    get changes_path(year: 2024)
    assert_select "td", text: "金額の誤り"
    get changes_path(after_close: 1)
    assert_select "tbody tr", 1
    get changes_path(after_close: 1, print: 1)
    assert_select "h1", text: "変更の記録"
  end
end
