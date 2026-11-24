# 役員の任期(年度をまたぐ)。締めた年度にかかる任期を変えるときは理由を書く。
class OfficerTermsController < ApplicationController
  include ClosedYearGuard

  before_action { @person = Person.find(params[:person_id]) }

  def create
    t = @person.officer_terms.new(params.require(:officer_term).permit(:starts_on, :ends_on, :left_on, :remunerated, :appointed_by, :notes))
    t.role = params.dig(:officer_term, :role).presence_in(OfficerTerm::ROLES.keys) # 役員の役名(権限ではない)
    return redirect_to(@person, alert: @reason_needed) unless closed_year_reason_ok?(fiscal_years_between(t.starts_on, t.left_on || t.ends_on), "役員の任期")

    t.save ? redirect_to(@person, notice: "役員の任期を追加しました") : redirect_to(@person, alert: t.errors.full_messages.join(" / "))
  end

  def destroy
    t = @person.officer_terms.find(params[:id])
    return redirect_to(@person, alert: @reason_needed) unless closed_year_reason_ok?(fiscal_years_between(t.starts_on, t.left_on || t.ends_on), "役員の任期")

    t.destroy!
    redirect_to @person, notice: "削除しました"
  end
end
