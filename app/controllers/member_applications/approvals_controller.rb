# 入会を認めた(イベントを作る)。docs/adr/0008・0030: コントローラーは確かめ・呼び出し・表示の準備だけ。
class MemberApplications::ApprovalsController < ApplicationController
  def create
    a = MemberApplication.find(params[:member_application_id])
    person = Person.find(params[:person_id]) if params[:person_id].present?
    year = params[:fiscal_year].presence&.to_i || a.default_year
    joined = params[:joined_on].presence&.then { Date.parse(it) } || Date.current
    MemberApplication::Approval.approve!(a, fiscal_year: year, joined_on: joined, person:, by: Current.user)
    redirect_to member_application_path(a, anchor: "mail"), notice: "入会を認めました。#{year}年度の正会員になりました(元に戻せない操作です。間違えたときは人の記録と会員資格を直してください)"
  rescue ArgumentError, ActiveRecord::RecordInvalid => e # Date::Error は ArgumentError の仲間
    redirect_to a, alert: e.message
  end

  private

  def audit_scope = "member_applications"
end
