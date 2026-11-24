require "test_helper"

# 会員資格・役員の任期・法人情報を HTML の画面で直す。締めた年度にかかるときは理由が要る。
class PeopleRecordsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    ensure_organization
    FiscalPeriod.ensure!
    FiscalPeriod.for(2023).close!
    @person = Person.create!(name: "会員A")
  end

  test "会員資格を足す・消す。締めた年度は理由を書く" do
    post person_memberships_path(@person), params: {membership: {fiscal_year: 2024, kind: "regular"}}
    assert_equal "会員資格を追加しました", flash[:notice]
    post person_memberships_path(@person), params: {membership: {fiscal_year: 2024, kind: "regular"}}
    assert flash[:alert].present?, "同じ年度・種別は二重に足さない"

    post person_memberships_path(@person), params: {membership: {fiscal_year: 2023, kind: "regular"}}
    assert_match "締めた年度です", flash[:alert]
    post person_memberships_path(@person), params: {membership: {fiscal_year: 2023, kind: "regular"}, reason: "名簿の漏れ"}
    old = @person.memberships.find_by!(fiscal_year: 2023)

    delete person_membership_path(@person, old)
    assert_match "締めた年度です", flash[:alert]
    delete person_membership_path(@person, old), params: {reason: "誤り"}
    assert_equal "削除しました", flash[:notice]
    assert_equal [2024], @person.memberships.reload.map(&:fiscal_year)
  end

  test "役員の任期を足す・消す。締めた年度にかかるなら理由を書く" do
    post person_officer_terms_path(@person), params: {officer_term: {role: "director", starts_on: "", ends_on: ""}}
    assert flash[:alert].present?, "任期の日付が無ければ足さない"

    term = {role: "director", starts_on: "2023-07-01", ends_on: "2025-06-30"}
    post person_officer_terms_path(@person), params: {officer_term: term}
    assert_match "2023年度", flash[:alert]
    post person_officer_terms_path(@person), params: {officer_term: term, reason: "記録の漏れ"}
    assert_equal "役員の任期を追加しました", flash[:notice]
    t = @person.officer_terms.sole
    assert_equal "director", t.role

    delete person_officer_term_path(@person, t)
    assert_match "締めた年度です", flash[:alert]
    delete person_officer_term_path(@person, t), params: {reason: "誤り"}
    assert_not OfficerTerm.exists?(t.id)
  end

  test "法人情報: 操作している年度の記録を直す。締めた年度は理由を書く" do
    get edit_organization_path
    assert_response :success

    get year_switch_path(2023)
    patch organization_path, params: {organization: {representative_name: "代表A"}}
    assert_response :unprocessable_entity
    patch organization_path, params: {organization: {representative_name: "代表A"}, reason: "登記に合わせる"}
    assert_redirected_to organization_path
    assert_equal "代表A", Organization.first.record_for(2023).representative_name

    get year_switch_path(2024)
    patch organization_path, params: {organization: {name: ""}}
    assert_response :unprocessable_entity
    assert flash[:alert].present?
    org = Organization.first
    assert_equal "テスト法人", org.name, "空の名前は保存しない(本体の列)"
    assert_equal "テスト法人", org.at(2024).name, "空の名前は保存しない(操作している年度の記録)"
    assert_equal "テスト法人", org.record_for(2023).name

    first_year = org.first_fiscal_year
    patch organization_path, params: {organization: {first_fiscal_year: "abc", name: "テスト法人"}}
    assert_response :unprocessable_entity
    assert_match "第 1 期の年度は数値で入力してください", flash[:alert]
    assert_equal first_year, org.reload.first_fiscal_year, "数でない値で第 1 期の年度を消さない"
  end
end
