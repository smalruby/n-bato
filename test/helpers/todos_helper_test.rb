require "test_helper"

class TodosHelperTest < ActionView::TestCase
  test "年度の札: 令和は R(2019 年度は元)、それより前は H" do
    assert_match "R元", year_chip(2019)
    assert_match "R6", year_chip(2024)
    assert_match "H30", year_chip(2018)
    assert_match "年度なし", year_chip(nil)
  end
end
