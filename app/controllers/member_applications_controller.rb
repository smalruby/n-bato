# 入会申込(デザインシステム「入会申込」)。届いた申込を見て、入会を認める・認めない。
class MemberApplicationsController < ApplicationController
  undoable_screen
  before_action :set_application, only: %i[show approve reject]
  before_action :forbid_auditor, only: %i[approve reject]

  def index
    @applications = MemberApplication.ordered
  end

  def show
    @same = @application.same_name_people
  end

  def approve
    a = @application
    person = Person.find(params[:person_id]) if params[:person_id].present?
    year = params[:fiscal_year].presence&.to_i || a.default_year
    joined = params[:joined_on].presence&.then { Date.parse(it) } || Date.current
    Audit.label!("#{a.name}さんの入会を認めた(#{year}年度の正会員)")
    MemberApplication::Approval.approve!(a, fiscal_year: year, joined_on: joined, person:, by: Current.user)
    redirect_to member_application_path(a, anchor: "mail"), notice: "入会を認めました。#{year}年度の正会員になりました(元に戻せない操作です。間違えたときは人の記録と会員資格を直してください)"
  rescue ArgumentError, Date::Error, ActiveRecord::RecordInvalid => e
    redirect_to a, alert: e.message
  end

  def reject
    Audit.label!("#{@application.name}さんの入会申込を認めないことにした")
    MemberApplication::Rejection.reject!(@application, reason: params[:reason], by: Current.user)
    redirect_to @application, notice: "認めないことにしました(元に戻せない操作です)"
  rescue ArgumentError => e
    redirect_to @application, alert: e.message
  end

  private

  def set_application = @application = MemberApplication.find(params[:id])
  def forbid_auditor = (redirect_to(@application, alert: "監査の役割では変えられません") if Current.user&.auditor?)
end
