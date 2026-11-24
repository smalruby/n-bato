require "test_helper"

class OrganizationTest < ActiveSupport::TestCase
  test "年度の記録の名前も空にできない(本体の列に空の名前が写らない)" do
    org = Organization.create!(name: "テスト法人", first_fiscal_year: 2024)
    record = org.year_record!(FiscalYear.current.year)
    assert_not record.update(name: "")
    assert_equal "テスト法人", org.reload.name
    assert_includes record.errors.full_messages, "法人名を入力してください"
  end

  test "第 1 期の年度は整数だけ(数でない値は捨てずに断る)" do
    org = Organization.create!(name: "テスト法人", first_fiscal_year: 2024)
    assert_not org.update(first_fiscal_year: "abc")
    assert_includes org.errors.full_messages, "第 1 期の年度は数値で入力してください"
    assert org.update(first_fiscal_year: ""), "空にはできる"
    assert_nil org.reload.first_fiscal_year
  end
end
