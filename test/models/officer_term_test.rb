require "test_helper"

class OfficerTermTest < ActiveSupport::TestCase
  setup do
    @a = Person.create!(name: "役員A", address: "島根県テスト市1-1")
    @b = Person.create!(name: "役員B")
    @term = OfficerTerm.create!(person: @a, role: "chair", starts_on: Date.new(2022, 7, 1), ends_on: Date.new(2024, 6, 30))
  end

  test "任期が満了しても次の選任までは職務を続ける" do
    assert @term.serving_on?(Date.new(2025, 1, 1))
    assert @term.holdover_on?(Date.new(2025, 1, 1))
    assert_equal Date.new(2025, 4, 1)..Date.new(2026, 3, 31), @term.period_in(FiscalYear.new(2025))
  end

  test "次の選任の前日まで" do
    OfficerTerm.create!(person: @b, role: "chair", starts_on: Date.new(2026, 12, 10), ends_on: Date.new(2028, 12, 9))
    assert_not @term.serving_on?(Date.new(2026, 12, 10))
    assert_equal Date.new(2026, 4, 1)..Date.new(2026, 12, 9), @term.period_in(FiscalYear.new(2026))
    assert_equal [ "役員B" ], OfficerTerm.serving_on(Date.new(2027, 1, 1)).map { it.person.name }
  end

  test "住所は暗号化して保存する" do
    raw = Person.connection.select_value("SELECT address FROM people WHERE id = #{@a.id}")
    assert_no_match "島根県", raw
    assert_equal "島根県テスト市1-1", @a.reload.address
  end
end
