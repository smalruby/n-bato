require "test_helper"

# 入会を認めた・認めなかったを詳細のイベントにする(見直し第20回、docs/adr/0030)。値は架空。
class MemberApplicationEventsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @a = MemberApplication.create!(name: "申込　太郎", applied_on: Date.new(2026, 5, 1), address: "テスト市1", postal_code: "000-0000")
  end

  test "認める: 人・正会員の資格・イベントができ、状態が決まる" do
    e = MemberApplication::Approval.approve!(@a, fiscal_year: 2026, joined_on: Date.new(2026, 5, 10), by: @user)
    @a.reload
    assert_equal "approved", @a.status
    assert_equal "approved", @a.derived_status
    assert_equal e.person, @a.person
    assert_equal "〒000-0000 テスト市1", e.person.address
    assert e.person.member_in?(2026)
    assert_empty ModelVerification.member_application_mismatches
    assert_raises(ArgumentError) { MemberApplication::Approval.approve!(@a, fiscal_year: 2026, joined_on: Date.current) }
  end

  test "操作履歴の名前は入口で付ける(rake や AI から起こしても同じ名前)" do
    Audit.operation(user: @user, scope: "member_applications") { MemberApplication::Approval.approve!(@a, fiscal_year: 2026, joined_on: Date.current, by: @user) }
    assert_equal ["申込　太郎さんの入会を認めた(2026年度の正会員)", "final"], AuditOperation.order(:id).last.then { [it.label, it.kind] }
    b = MemberApplication.create!(name: "申込　次郎", applied_on: Date.current)
    Audit.operation(user: @user, scope: "member_applications") { MemberApplication::Rejection.reject!(b, reason: "連絡がとれない", by: @user) }
    assert_equal ["申込　次郎さんの入会申込を認めないことにした", "final"], AuditOperation.order(:id).last.then { [it.label, it.kind] }
  end

  test "締めた年度には認められない" do
    FiscalPeriod.create!(year: 2025, closed_on: Date.current)
    assert_raises(ArgumentError) { MemberApplication::Approval.approve!(@a, fiscal_year: 2025, joined_on: Date.current) }
  end

  test "認めない: 理由は必須" do
    assert_raises(ArgumentError) { MemberApplication::Rejection.reject!(@a, reason: " ") }
    MemberApplication::Rejection.reject!(@a, reason: "定款の目的に合わない", by: @user)
    assert_equal "rejected", @a.reload.derived_status
    assert_equal "定款の目的に合わない", @a.reason
    assert_raises(ArgumentError) { MemberApplication::Rejection.reject!(@a, reason: "もう一度") }
  end

  test "model:verify: 状態や入会日のずれを見つける" do
    MemberApplication::Approval.approve!(@a, fiscal_year: 2026, joined_on: Date.new(2026, 5, 10))
    @a.update_columns(joined_on: Date.new(2026, 5, 11))
    b = MemberApplication.create!(name: "申込　次郎", applied_on: Date.current, status: "approved")
    m = ModelVerification.member_application_mismatches
    assert(m.any? { it.include?("##{@a.id}: 認めたときの") })
    assert(m.any? { it.include?("##{b.id}: いまの状態") })
  end

  test "model:verify: 氏名の出来事のつながりのずれを見つける" do
    p = Person.create!(name: "田中　花子")
    c = Person::NameChange.record!(p, name: "鈴木　花子", changed_on: Date.current)
    c.update_columns(former_name: "別の　人")
    assert(ModelVerification.person_history_mismatches.any? { it.include?("人 ##{p.id}") })
  end
end
