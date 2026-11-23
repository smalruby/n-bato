require "test_helper"

class Ledger::BookTest < ActiveSupport::TestCase
  setup do
    Kaikeiou::SiwakeImporter.new(file_fixture("siwake_sample.txt").binread, filename: "s.txt").import
    OpeningBalance.create!(fiscal_year: 2024, account: Account.find_by!(code: 100), amount: 10_000)
  end

  test "活動計算書と貸借対照表がつながる" do
    s = Ledger::Book.new.statement(2024)
    assert_equal 10_000, s.opening_net_assets
    assert_equal 5000 + 2000 + 3, s.revenue_total
    assert_equal 1200, s.program_expense_total
    assert_equal 84, s.admin_expense_total
    assert_equal 5719, s.net_assets_change
    assert_equal 15_719, s.closing_net_assets
    assert s.balanced?
    cash = Account.find_by!(code: 100)
    bank = Account.find_by!(code: 106)
    assert_equal 10_000 + 5000 - 1200 - 3000 + 2000 - 84, s.closing_balances[cash]
    assert_equal 3003, s.closing_balances[bank]
    assert_equal({ Department.find_by!(code: 113) => 1200 }, s.program_expense_by_department)
  end

  test "仕訳の無い年度は前年度末を繰り越す" do
    travel_to Date.new(2027, 1, 1) do
      book = Ledger::Book.new
      assert_equal [ 2024, 2025 ], book.years
      s = book.statement(2025)
      assert_equal 15_719, s.opening_net_assets
      assert_equal 0, s.net_assets_change
      assert_equal 15_719, s.closing_net_assets
    end
  end
end
