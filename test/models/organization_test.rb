require "test_helper"

class OrganizationTest < ActiveSupport::TestCase
  test "年度の記録の名前も空にできない(本体の列に空の名前が写らない)" do
    org = Organization.create!(name: "テスト法人", first_fiscal_year: 2024)
    record = org.year_record!(FiscalYear.current.year)
    assert_not record.update(name: "")
    assert_equal "テスト法人", org.reload.name
  end
end
