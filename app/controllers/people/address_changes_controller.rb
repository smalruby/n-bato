# 住所が変わった(出来事を足す。docs/adr/0029)
class People::AddressChangesController < ApplicationController
  def create
    person = Person.find(params[:person_id])
    return redirect_to(person, alert: "監査の役割では記録できません") if Current.user&.auditor?

    on, precision = Person::AddressChange.parse_date(year: params[:year], month: params[:month], day: params[:day])
    Person::AddressChange.record!(person, address: params[:address], moved_on: on, date_precision: precision, by: Current.user, note: params[:note])
    redirect_to person_path(person, anchor: "person-history"), notice: "住所が変わったことを記録しました"
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to person_path(person, anchor: "person-history"), alert: e.message
  end

  private

  def audit_scope = "people"
end
