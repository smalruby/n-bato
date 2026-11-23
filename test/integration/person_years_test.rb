require "test_helper"

# 会員・役員の年度ごとの記録(デザインシステム「年度」)
class PersonYearsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    [ 2024, 2025, 2026 ].each { FiscalPeriod.find_or_create_by!(year: it) }
    Current.working_year = 2026
    @person = Person.create!(name: "会員A", address: "テスト市1")
    Current.working_year = nil
  end

  test "直すのは操作している年度の記録だけで、ほかの年度にも同じ値があれば直すかを聞く" do
    get people_path(year: 2025)
    patch person_path(@person), params: { person: { name: "会員A", address: "テスト市2" } }
    follow_redirect!
    assert_equal "テスト市2", @person.reload.record_for(2025).address
    assert_equal "テスト市1", @person.record_for(2026).address
    assert_select "form[action='#{apply_to_years_person_path(@person)}']"

    post apply_to_years_person_path(@person), params: { from: 2025, fields: [ "address" ], years: [ 2026 ] }
    assert_equal "テスト市2", @person.reload.record_for(2026).address
  end

  test "締めた年度の記録は理由を書かないと直せない" do
    FiscalPeriod.for(2024).update!(closed_on: Date.current)
    get people_path(year: 2024)
    patch person_path(@person), params: { person: { name: "会員A", address: "テスト市9" } }
    assert_response :unprocessable_entity
    assert_nil @person.reload.record_for(2024)

    patch person_path(@person), params: { person: { name: "会員A", address: "テスト市9" }, reason: "住所の打ち間違い" }
    assert_equal "テスト市9", @person.reload.record_for(2024).address
    assert_equal "住所の打ち間違い", AuditOperation.order(:id).last.reason
  end

  test "その年度の記録が無い人は、近い年度の記録を出してそう書く" do
    get person_path(@person, year: 2025)
    assert_select ".nb-flash", text: /2025年度の記録がないため、2026年度の記録を出しています/
  end
end
