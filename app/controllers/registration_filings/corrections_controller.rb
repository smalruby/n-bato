class RegistrationFilings::CorrectionsController < RegistrationFilings::EventsController
  def create
    RegistrationFiling::Correction.record!(@filing, noticed_on: date_param, note: params[:note], by: Current.user)
    done "補正を求められたことを記録しました"
  rescue ArgumentError => e
    failed(e)
  end
end
