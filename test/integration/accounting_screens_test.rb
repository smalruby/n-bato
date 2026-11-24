require "test_helper"

# 会計の画面(年度の一覧・期首残高・残高照合・取り込みの記録・科目・仕訳の HTML の画面・元に戻す)
class AccountingScreensTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    ensure_organization
    @cash = Account.create!(fiscal_year: 2024, code: 100, name: "現      金")
    @supplies = Account.create!(fiscal_year: 2024, code: 658, name: "消耗品費(事業)")
    FiscalPeriod.ensure!
    get year_switch_path(2024)
  end

  def entry(**attrs) = JournalEntry.create!(entry_date: Date.new(2024, 5, 1), debit_account: @supplies, credit_account: @cash, amount: 1000, summary: "文具", **attrs)

  test "年度の一覧" do
    entry
    get fiscal_years_path
    assert_response :success
  end

  test "期首残高: 登録・登録できない科目・削除" do
    get opening_balances_path
    assert_response :success

    post opening_balances_path, params: {opening_balance: {fiscal_year: 2024, account_id: @cash.id, amount: 1200}}
    assert_equal "期首残高を登録しました", flash[:notice]
    balance = OpeningBalance.find_by!(account: @cash)
    assert_equal 1200, balance.amount

    post opening_balances_path, params: {opening_balance: {fiscal_year: 2024, account_id: @supplies.id, amount: 5}}
    assert_match "貸借対照表の科目", flash[:alert]

    delete opening_balance_path(balance)
    assert_not OpeningBalance.exists?(balance.id)
  end

  test "残高照合: 資産の科目でなければ登録しない。削除できる" do
    post balance_checks_path, params: {balance_check: {checked_on: "2024-06-01", actual_amount: 100, account_id: @supplies.id}}
    assert_redirected_to balance_checks_path
    assert flash[:alert].present?
    assert_equal 0, BalanceCheck.count

    check = BalanceCheck.create!(account: @cash, checked_on: Date.new(2024, 6, 1), actual_amount: 0)
    delete balance_check_path(check)
    assert_equal "削除しました", flash[:notice]
    assert_not BalanceCheck.exists?(check.id)
  end

  test "取り込みの記録を開く" do
    import_sample
    get siwake_import_path(SiwakeImport.last)
    assert_response :success
    assert_match "siwake_sample.txt", response.body
  end

  test "科目の区分を HTML の画面で直す" do
    get edit_account_path(@supplies)
    assert_response :success

    patch account_path(@supplies), params: {account: {category: "admin_expense"}}
    assert_redirected_to accounts_path
    assert_equal "admin_expense", @supplies.reload.category

    patch account_path(@supplies), params: {account: {category: "ない区分"}}
    assert_response :unprocessable_entity
  end

  test "仕訳の HTML の画面: 保存できなければ画面に戻す" do
    post journal_entries_path, params: {journal_entry: {entry_date: "", amount: "1", debit_account_id: @supplies.id, credit_account_id: @cash.id}}
    assert_response :unprocessable_entity

    e = entry
    patch journal_entry_path(e), params: {journal_entry: {summary: "ノート"}}
    assert_redirected_to journal_entries_path(year: 2024)
    assert_equal "ノート", e.reload.summary

    patch journal_entry_path(e), params: {journal_entry: {credit_account_id: @supplies.id}}
    assert_response :unprocessable_entity
  end

  test "まだ始めていない年度の日付は保存しない" do
    post journal_entries_path(format: :json), params: {sheet_year: 2024, journal_entry: {entry_date: "2031-05-01", amount: "1", debit_account_id: @supplies.id, credit_account_id: @cash.id}}
    assert_response :conflict
    assert_equal "no_year", response.parsed_body["code"]
    assert_match "2031年度はまだ始めていません", response.parsed_body["message"]
  end

  test "仕訳を消す。締めた年度は理由が要る" do
    e = entry
    delete journal_entry_path(e)
    assert_not JournalEntry.exists?(e.id)

    e = entry
    FiscalPeriod.for(2023).close!
    FiscalPeriod.for(2024).close!
    delete journal_entry_path(e)
    assert_match "締めた年度です", flash[:alert]
    assert JournalEntry.exists?(e.id)

    delete journal_entry_path(e), params: {reason: "二重に入れていた"}
    assert_not JournalEntry.exists?(e.id)
    op = AuditOperation.order(:id).last
    assert_equal ["二重に入れていた", "締めた年度(2024年度)の仕訳を消した"], [op.reason, op.label]
  end

  test "科目の変更を元に戻すと科目の画面へ。そのあと別の画面で変わっていたら知らせる" do
    patch account_path(@supplies, format: :json), params: {account: {group_name: "備品"}, undo_scope: "accounts"}
    post undo_path(format: :json), params: {scope: "accounts"}
    assert_equal accounts_path, response.parsed_body["location"]
    assert_nil @supplies.reload.group_name

    post redo_path(format: :json), params: {scope: "accounts"}
    patch account_path(@supplies, format: :json), params: {account: {group_name: "文具"}, undo_scope: "other"}
    post undo_path(format: :json), params: {scope: "accounts"}
    assert_response :conflict
    assert_match "別の操作で変わっています", response.parsed_body["message"]

    post undo_path, params: {scope: "accounts"}, headers: {"HTTP_REFERER" => accounts_url}
    assert_redirected_to accounts_url
    assert_match "別の操作で変わっています", flash[:alert]
  end
end
