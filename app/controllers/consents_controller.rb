class ConsentsController < ApplicationController
  before_action { @resolution = ::Resolution.find(params[:resolution_id]) }

  def create
    consent = @resolution.consents.new(params.require(:consent).permit(:consented_on, :via, :note))
    consent.person = Person.find(params.dig(:consent, :person_id))
    if consent.save
      msg = "#{consent.person.name} さんの同意を記録しました"
      msg += "。全員の同意がそろい、#{@resolution.established_on} に決議が成立しました" if @resolution.established?
      redirect_to @resolution, notice: msg
    else
      redirect_to @resolution, alert: consent.errors.full_messages.join(" / ")
    end
  end

  def destroy
    @resolution.consents.find(params[:id]).destroy!
    redirect_to @resolution, notice: "同意の記録を取り消しました"
  end
end
