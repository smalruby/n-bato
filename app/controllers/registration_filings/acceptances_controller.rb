class RegistrationFilings::AcceptancesController < RegistrationFilings::EventsController
  def create
    RegistrationFiling::Acceptance.accept!(@filing, accepted_on: date_param, receipt_number: params[:receipt_number], by: Current.user)
    done "受け付けられたことを記録しました"
  rescue ArgumentError => e
    failed(e)
  end
end
