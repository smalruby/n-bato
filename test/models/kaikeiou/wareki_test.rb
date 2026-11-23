require "test_helper"

class Kaikeiou::WarekiTest < ActiveSupport::TestCase
  test "会計王は令和以降も平成で数える" do
    assert_equal Date.new(2024, 4, 15), Kaikeiou::Wareki.parse("H.36/04/15")
    assert_equal Date.new(2017, 4, 7), Kaikeiou::Wareki.parse("H.29/04/07")
    assert_equal Date.new(2025, 4, 1), Kaikeiou::Wareki.parse("R.07/04/01")
    assert_equal "H.36/04/15", Kaikeiou::Wareki.format(Date.new(2024, 4, 15))
    assert_equal "S.63/12/31", Kaikeiou::Wareki.format(Date.new(1988, 12, 31))
  end

  test "読めない日付はエラー" do
    assert_raises(ArgumentError) { Kaikeiou::Wareki.parse("2024/04/15") }
  end
end
