require "test_helper"

class Ledger::BalanceTest < ActiveSupport::TestCase
  setup do
    Kaikeiou::SiwakeImporter.new(file_fixture("siwake_sample.txt").binread, filename: "s.txt").import
    @cash = Account.find_by!(code: 100)
    @bank = Account.find_by!(code: 106)
    OpeningBalance.create!(fiscal_year: 2024, account: @cash, amount: 10_000)
  end

  test "指定日の残高" do
    book = Ledger::Book.new
    assert_equal 0, book.balance_as_of(@bank, Date.new(2024, 5, 31))
    assert_equal 3000, book.balance_as_of(@bank, Date.new(2024, 6, 1))
    assert_equal 3003, book.balance_as_of(@bank, Date.new(2025, 3, 31))
    assert_equal 0, book.balance_as_of(@bank, Date.new(2020, 1, 1))
  end

  test "残高照合で差を出す" do
    check = BalanceCheck.create!(account: @bank, checked_on: Date.new(2025, 3, 31), actual_amount: 3010)
    assert_equal 7, check.difference
  end

  test "元帳の残高の推移" do
    ledger = Ledger::Book.new.account_ledger(@cash, 2024)
    assert_equal 10_000, ledger[:opening]
    assert_equal [ 15_000, 13_800, 10_800, 12_800, 12_716 ], ledger[:rows].pluck(:balance)
    assert_equal 12_716, ledger[:closing]
  end
end
