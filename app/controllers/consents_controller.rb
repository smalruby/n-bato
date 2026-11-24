# 書面決議への同意を記録する(イベント。docs/adr/0038)。取り消すは Consents::CancellationsController。
class ConsentsController < ApplicationController
  before_action { @resolution = ::Resolution.find(params[:resolution_id]) }

  def create
    attrs = params.require(:consent).permit(:consented_on, :via, :note)
    consent = Consent.record!(@resolution, person: Person.find(params.dig(:consent, :person_id)),
      consented_on: attrs[:consented_on], via: attrs[:via], note: attrs[:note])
    msg = "#{consent.person.name} さんの同意を記録しました"
    msg += "。全員の同意がそろい、#{@resolution.established_on} に決議が成立しました" if @resolution.reload.established?
    redirect_to @resolution, notice: msg
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @resolution, alert: e.record.errors.full_messages.join(" / ")
  end
end
