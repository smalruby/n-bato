# 氏名が変わった(出来事を足す。docs/adr/0029)
class People::NameChangesController < ApplicationController
  def create
    person = Person.find(params[:person_id])
    return redirect_to(person, alert: "監査の役割では記録できません") if Current.user&.auditor?

    on, precision = Person::NameChange.parse_date(year: params[:year], month: params[:month], day: params[:day])
    Person::NameChange.record!(person, name: params[:name], name_kana: params[:name_kana], changed_on: on, date_precision: precision,
                                       show_former_name: params[:show_former_name], by: Current.user, note: params[:note])
    redirect_to person_path(person, anchor: "person-history"), notice: "氏名が変わったことを記録しました"
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to person_path(person, anchor: "person-history"), alert: e.message
  end

  private

  def audit_scope = "people"
end
