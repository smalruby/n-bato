# 入会を認めなかった(イベントを作る)。docs/adr/0008・0030
class MemberApplications::RejectionsController < ApplicationController
  def create
    a = MemberApplication.find(params[:member_application_id])
    MemberApplication::Rejection.reject!(a, reason: params[:reason], by: Current.user)
    redirect_to a, notice: "認めないことにしました(元に戻せない操作です)"
  rescue ArgumentError => e
    redirect_to a, alert: e.message
  end

  private

  def audit_scope = "member_applications"
end
