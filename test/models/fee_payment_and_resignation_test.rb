require "test_helper"

# 会費の納入と役員の退任をイベントにする(#17、docs/adr/0030)。値は架空。
class FeePaymentAndResignationTest < ActiveSupport::TestCase
  setup do
    Organization.first || Organization.create!(name: "テスト法人", first_fiscal_year: 2023)
    @user = users(:one)
    @person = Person.create!(name: "会員B")
    @membership = @person.memberships.create!(fiscal_year: 2026, kind: "regular")
    @term = @person.officer_terms.create!(role: "director", starts_on: Date.new(2026, 6, 1), ends_on: Date.new(2028, 5, 31))
  end

  test "会費の納入: イベントができ、会員資格から読める" do
    payment = Membership::FeePayment.record!(@membership, amount: "3000", paid_on: "2026-06-10", by: @user)
    assert_equal [3000, Date.new(2026, 6, 10), @user], [payment.amount, payment.paid_on, payment.recorder]
    assert @membership.fee_paid?
    assert_equal payment, @membership.reload.fee_payment
    assert_equal 2026, payment.audit_fiscal_year
  end

  test "会費の納入: 日付・金額を確かめ、二度は記録しない" do
    assert_raises(ArgumentError, match: "納めた日") { Membership::FeePayment.record!(@membership, amount: 1000, paid_on: "") }
    assert_raises(ArgumentError, match: "金額") { Membership::FeePayment.record!(@membership, amount: -1, paid_on: Date.current) }
    assert_raises(ArgumentError, match: "金額") { Membership::FeePayment.record!(@membership, amount: "千円", paid_on: Date.current) }
    Membership::FeePayment.record!(@membership, amount: 0, paid_on: Date.current)
    assert_raises(ArgumentError, match: "もう納めた") { Membership::FeePayment.record!(@membership, amount: 1000, paid_on: Date.current) }
  end

  test "退任: イベントができ、職務の最後の日が退任の日になる" do
    resignation = OfficerTerm::Resignation.resign!(@term, left_on: "2027-01-15", reason: " 一身上の都合 ")
    assert_equal [Date.new(2027, 1, 15), "一身上の都合", nil], [resignation.left_on, resignation.reason, resignation.recorder]
    assert_equal Date.new(2027, 1, 15), @term.left_on
    assert_equal Date.new(2027, 1, 15), @term.last_day
    assert @term.serving_on?(Date.new(2027, 1, 15))
    assert_not @term.serving_on?(Date.new(2027, 1, 16))
    assert_equal 2026, resignation.audit_fiscal_year
    assert_not_includes OfficerTerm.serving_on(Date.new(2027, 2, 1)), @term
  end

  test "退任: 日付を確かめ、二度は記録しない" do
    assert_raises(ArgumentError, match: "退任した日を") { OfficerTerm::Resignation.resign!(@term, left_on: nil) }
    assert_raises(ArgumentError, match: "就任日より後") { OfficerTerm::Resignation.resign!(@term, left_on: "2026-05-31") }
    OfficerTerm::Resignation.resign!(@term, left_on: "2026-06-01")
    assert_raises(ArgumentError, match: "もう退任") { OfficerTerm::Resignation.resign!(@term, left_on: "2026-07-01") }
  end

  test "操作履歴の名前は入口で付ける(元に戻せない操作)" do
    Audit.operation(user: @user, scope: "people") { Membership::FeePayment.record!(@membership, amount: 3000, paid_on: Date.new(2026, 6, 10), by: @user) }
    assert_equal ["会員Bさんの2026年度の会費の納入を記録した", "final"], AuditOperation.order(:id).last.then { [it.label, it.kind] }
    Audit.operation(user: @user, scope: "people") { OfficerTerm::Resignation.resign!(@term, left_on: Date.new(2027, 1, 15), by: @user) }
    assert_equal ["会員Bさんが理事を退任した(2027/01/15)", "final"], AuditOperation.order(:id).last.then { [it.label, it.kind] }
  end

  test "記録のある会員資格・任期は消せない" do
    Membership::FeePayment.record!(@membership, amount: 3000, paid_on: Date.current)
    OfficerTerm::Resignation.resign!(@term, left_on: Date.new(2027, 1, 15))
    assert_not @membership.destroy
    assert_not @term.destroy
  end
end
