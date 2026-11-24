require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "科目性格コードから区分を決める" do
    assert_equal "asset", Account.category_for_nature(11150)
    assert_equal "liability", Account.category_for_nature(12110)
    assert_equal "net_assets", Account.category_for_nature(13100)
    assert_equal "revenue", Account.category_for_nature(21110)
    assert_equal "program_expense", Account.category_for_nature(21122)
    assert_equal "admin_expense", Account.category_for_nature(21182)
    assert_equal "extraordinary", Account.category_for_nature(22100)
    assert_equal "tax", Account.category_for_nature(23000)
    assert_equal "net_assets", Account.category_for_nature(23002)
    assert_equal "special", Account.category_for_nature(40001)
  end

  test "標準の範囲に無い科目コードは特別・非財務" do
    account = Account.create!(fiscal_year: 2024, code: 999, name: "対照勘定")
    assert_equal "special", account.category
    assert_not account.balance_sheet?
    assert_not account.activity?
  end
end
