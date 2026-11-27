# 会員資格(年度ごと)。締めた年度の会員資格を変えるときは理由を書く。
class MembershipsController < ApplicationController
  include ClosedYearGuard

  before_action { @person = Person.find(params[:person_id]) }

  def create
    m = @person.memberships.new(params.require(:membership).permit(:fiscal_year, :kind, :joined_on)) # 会費の納入はイベント(Membership::FeePayment)
    return redirect_to(@person, alert: @reason_needed) unless closed_year_reason_ok?(m.fiscal_year, "会員資格")

    m.save ? redirect_to(@person, notice: "会員資格を追加しました") : redirect_to(@person, alert: m.errors.full_messages.join(" / "))
  end

  def destroy
    m = @person.memberships.find(params[:id])
    return redirect_to(@person, alert: @reason_needed) unless closed_year_reason_ok?(m.fiscal_year, "会員資格")

    m.destroy ? redirect_to(@person, notice: "削除しました") : redirect_to(@person, alert: "会費を納めた記録があるので消せません")
  end
end
