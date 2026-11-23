require "test_helper"

# 科目と部門は年度ごとのデータセット(デザインシステム「年度」)
class YearlyDatasetTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    [ 2024, 2025 ].each do |y|
      Account.create!(fiscal_year: y, code: 100, name: "現金")
      Account.create!(fiscal_year: y, code: 658, name: "消耗品費(事業)")
    end
    FiscalPeriod.ensure!
    @entry = JournalEntry.create!(entry_date: Date.new(2024, 5, 1), debit_account: Account.for_year(2024, 658), credit_account: Account.for_year(2024, 100), amount: 1000)
  end

  test "仕訳を別の年度へ移すと、移した年度の同じコードの科目に付け替える" do
    patch journal_entry_path(@entry, format: :json), params: { journal_entry: { entry_date: "2025-04-10" }, sheet_year: 2024, move: "1", undo_scope: "journal_entries" }
    assert response.parsed_body["ok"]
    @entry.reload
    assert_equal [ 2025, 2025 ], [ @entry.debit_account.fiscal_year, @entry.credit_account.fiscal_year ]
  end

  test "移した年度に科目が無ければ保存しない" do
    Account.for_year(2025, 658).destroy!
    patch journal_entry_path(@entry, format: :json), params: { journal_entry: { entry_date: "2025-04-10" }, sheet_year: 2024, move: "1", undo_scope: "journal_entries" }
    assert_response :unprocessable_entity
    assert_match "2025年度にありません", response.parsed_body["message"]
  end

  test "科目と部門の画面は操作している年度の科目を出し、直したらほかの締めていない年度にも効かせるかを聞く" do
    get accounts_path(year: 2024)
    assert_select "input[name='account[group_name]']", Account.in_year(2024).count
    account = Account.for_year(2024, 658)
    patch account_path(account, format: :json), params: { account: { group_name: "人件費" }, undo_scope: "accounts" }
    also = response.parsed_body["also"]
    assert_includes also["years"], 2025

    post apply_to_years_account_path(account, format: :json), params: { field: "group_name", years: [ 2025 ], undo_scope: "accounts" }
    assert_equal "人件費", Account.for_year(2025, 658).group_name
  end

  test "締めた年度の科目は理由を書かないと直せない" do
    FiscalPeriod.for(2024).update!(closed_on: Date.current)
    account = Account.for_year(2024, 658)
    patch account_path(account, format: :json), params: { account: { group_name: "人件費" }, undo_scope: "accounts" }
    assert_equal "reason_required", response.parsed_body["code"]
    patch account_path(account, format: :json), params: { account: { group_name: "人件費" }, reason: "区分の誤り", undo_scope: "accounts" }
    assert response.parsed_body["ok"]
  end
end
