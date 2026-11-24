require "test_helper"

# 会員・役員の年度ごとの記録(デザインシステム「年度」)
class PersonYearsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    [2024, 2025, 2026].each { FiscalPeriod.find_or_create_by!(year: it) }
    Current.working_year = 2026
    @person = Person.create!(name: "会員A", address: "テスト市1", phone: "000-0000-0001")
    Current.working_year = nil
  end

  test "直すのは操作している年度の記録だけで、ほかの年度にも同じ値があれば直すかを聞く" do
    get people_path(year: 2025)
    patch person_path(@person), params: {person: {phone: "000-0000-0002"}}
    follow_redirect!
    assert_equal "000-0000-0002", @person.reload.record_for(2025).phone
    assert_equal "000-0000-0001", @person.record_for(2026).phone
    assert_select "form[action='#{apply_to_years_person_path(@person)}']"

    post apply_to_years_person_path(@person), params: {from: 2025, fields: ["phone"], years: [2026]}
    assert_equal "000-0000-0002", @person.reload.record_for(2026).phone
  end

  test "締めた年度の記録は理由を書かないと直せない" do
    FiscalPeriod.for(2024).update!(closed_on: Date.current)
    get people_path(year: 2024)
    patch person_path(@person), params: {person: {phone: "000-0000-0009"}}
    assert_response :unprocessable_entity
    assert_nil @person.reload.record_for(2024)

    patch person_path(@person), params: {person: {phone: "000-0000-0009"}, reason: "電話の打ち間違い"}
    assert_equal "000-0000-0009", @person.reload.record_for(2024).phone
    assert_equal "電話の打ち間違い", AuditOperation.order(:id).last.reason
  end

  test "その年度の記録が無い人は、近い年度の記録を出してそう書く" do
    get person_path(@person, year: 2025)
    assert_select ".nb-flash", text: /2025年度の記録がないため、2026年度の記録を出しています/
  end
end
