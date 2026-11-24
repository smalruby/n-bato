require "test_helper"

# 会員・役員の画面(会員の作り替え。見直し第20回、docs/adr/0029)。値はすべて架空。
class PeopleTest < ActionDispatch::IntegrationTest
  setup { sign_in }

  test "登録する・名前が空なら登録しない・消す・消せないときは理由を出す" do
    get new_person_path
    assert_response :success
    post people_path, params: {person: {name: "", address: "テスト市1"}}
    assert_response :unprocessable_entity
    post people_path, params: {person: {name: "新しい　人", address: "テスト市1", phone: "000-0000-0000"}}
    person = Person.find_by_current_name("新しい　人")
    assert_redirected_to person
    assert_equal "000-0000-0000", person.phone
    OfficerTerm.create!(person:, role: "director", starts_on: Date.new(2024, 7, 1), ends_on: Date.new(2026, 6, 30))
    delete person_path(person)
    assert_redirected_to person
    assert flash[:alert].present?
    other = Person.create!(name: "消す　人")
    delete person_path(other)
    assert_redirected_to people_path
  end

  test "記録の始まりの氏名を空にすると保存しない" do
    person = Person.create!(name: "直す　人")
    patch person_path(person), params: {person: {name: ""}}
    assert_response :unprocessable_entity
  end

  test "監査の役割では、住所・氏名の出来事を記録・取消できない" do
    person = Person.create!(name: "監査　人", address: "テスト市1")
    users(:one).update!(role: "auditor")
    post person_address_changes_path(person), params: {address: "テスト市2", year: "2025", month: "4"}
    assert_match "監査", flash[:alert]
    post person_name_changes_path(person), params: {name: "別の　人", year: "2025", month: "4"}
    assert_match "監査", flash[:alert]
    post person_change_cancellation_path(person, change_type: "address", change_id: 1), params: {reason: "x"}
    assert_match "監査", flash[:alert]
    assert_not person.reload.changes_recorded?
  end

  test "入会を認めるときに日付が読めなければ、申込の画面に戻す" do
    a = MemberApplication.create!(name: "申込　人", applied_on: Date.current)
    post member_application_approval_path(a), params: {joined_on: "2026-13-40"}
    assert_redirected_to a
    assert flash[:alert].present?
  end
end
