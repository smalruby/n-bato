require "test_helper"

class FiscalPeriodTest < ActiveSupport::TestCase
  teardown { Current.reset }

  test "次の年度を始めると、法人の情報も前の年度から写す" do
    Current.working_year = 2024
    org = Organization.create!(name: "テスト法人", first_fiscal_year: 2023, representative_name: "代表 一郎")
    Current.working_year = nil
    FiscalPeriod.create!(year: 2024)

    period = FiscalPeriod.start_next!
    assert_equal 2025, period.year
    assert_equal "代表 一郎", org.reload.record_for(2025)&.representative_name
  end

  test "年度の状態: 記録が無い年度は分からない" do
    FiscalPeriod.create!(year: 2023, closed_on: Date.new(2024, 6, 1))
    FiscalPeriod.create!(year: 2024)
    FiscalPeriod.create!(year: 2025)
    assert_equal :closed, FiscalPeriod.state_of(2023)
    assert_equal :open, FiscalPeriod.state_of(2024)
    assert_equal :provisional, FiscalPeriod.state_of(2025)
    assert_equal :unknown, FiscalPeriod.state_of(2030)
  end
end
