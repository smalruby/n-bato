# 住所・氏名の出来事の取消(打ち間違いのとき。docs/adr/0029)
class People::ChangeCancellationsController < ApplicationController
  TYPES = {"address" => Person::AddressChange, "name" => Person::NameChange}.freeze

  def create
    person = Person.find(params[:person_id])
    return redirect_to(person, alert: "監査の役割では取り消せません") if Current.user&.auditor?

    change = TYPES.fetch(params[:change_type]).where(person:).find(params[:change_id])
    Person::ChangeCancellation.cancel!(change, by: Current.user, reason: params[:reason])
    redirect_to person_path(person, anchor: "person-history"), notice: "取り消しました。正しい内容で入れ直してください"
  rescue ArgumentError, KeyError => e
    redirect_to person_path(person, anchor: "person-history"), alert: e.message
  end

  private

  def audit_scope = "people"
end
